package backend

import (
	"context"
	"encoding/xml"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

const (
	ssdpMulticastAddr = "239.255.255.250:1900"
	ssdpTargetMediaRenderer = "urn:schemas-upnp-org:device:MediaRenderer:1"
	ssdpTargetAVTransport   = "urn:schemas-upnp-org:service:AVTransport:1"
)

// ssdpResponse holds a parsed SSDP M-SEARCH response.
type ssdpResponse struct {
	Location string
	USN      string
	ST       string
	Server   string
}

// msearch sends an M-SEARCH request for the given ST and collects responses
// within the timeout window. Sends twice (150ms apart) to improve hit rate.
func msearch(ctx context.Context, target string, timeout time.Duration) ([]ssdpResponse, error) {
	addr, err := net.ResolveUDPAddr("udp4", ssdpMulticastAddr)
	if err != nil {
		return nil, fmt.Errorf("resolve multicast: %w", err)
	}
	conn, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4zero, Port: 0})
	if err != nil {
		return nil, fmt.Errorf("listen udp: %w", err)
	}
	defer conn.Close()

	payload := fmt.Sprintf(
		"M-SEARCH * HTTP/1.1\r\n"+
			"HOST: %s\r\n"+
			"MAN: \"ssdp:discover\"\r\n"+
			"MX: 2\r\n"+
			"ST: %s\r\n"+
			"USER-AGENT: %s/%s UPnP/1.1\r\n"+
			"\r\n",
		ssdpMulticastAddr, target, AppName, Version,
	)

	// Send twice, 150ms apart.
	for i := 0; i < 2; i++ {
		if _, err := conn.WriteToUDP([]byte(payload), addr); err != nil {
			return nil, fmt.Errorf("sendto: %w", err)
		}
		if i == 0 {
			select {
			case <-time.After(150 * time.Millisecond):
			case <-ctx.Done():
				return nil, ctx.Err()
			}
		}
	}

	// Per-recv deadline: 200ms; keep collecting until overall timeout.
	deadline := time.Now().Add(timeout)
	buf := make([]byte, 8192)
	var responses []ssdpResponse

	for time.Now().Before(deadline) {
		remaining := time.Until(deadline)
		if remaining <= 0 {
			break
		}
		recvDeadline := 200 * time.Millisecond
		if remaining < recvDeadline {
			recvDeadline = remaining
		}
		_ = conn.SetReadDeadline(time.Now().Add(recvDeadline))

		n, _, err := conn.ReadFromUDP(buf)
		if err != nil {
			if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
				continue
			}
			if ctx.Err() != nil {
				return nil, ctx.Err()
			}
			continue
		}
		resp, ok := parseSSDPResponse(string(buf[:n]))
		if ok {
			responses = append(responses, resp)
		}
	}
	return responses, nil
}

// parseSSDPResponse parses a raw SSDP response string.
// Only accepts HTTP 200 OK responses (not NOTIFY).
func parseSSDPResponse(raw string) (ssdpResponse, bool) {
	lines := strings.Split(raw, "\r\n")
	if len(lines) == 0 {
		return ssdpResponse{}, false
	}
	first := strings.ToUpper(lines[0])
	if !strings.HasPrefix(first, "HTTP/1.1 200") && !strings.HasPrefix(first, "HTTP/1.0 200") {
		return ssdpResponse{}, false
	}
	var resp ssdpResponse
	for _, line := range lines[1:] {
		if line == "" {
			continue
		}
		colon := strings.IndexByte(line, ':')
		if colon < 0 {
			continue
		}
		name := strings.ToUpper(strings.TrimSpace(line[:colon]))
		value := strings.TrimSpace(line[colon+1:])
		switch name {
		case "LOCATION":
			resp.Location = value
		case "USN":
			resp.USN = value
		case "ST":
			resp.ST = value
		case "SERVER":
			resp.Server = value
		}
	}
	if resp.Location == "" {
		return ssdpResponse{}, false
	}
	return resp, true
}

// descriptionDevice holds the parsed fields from a UPnP device description XML.
type descriptionDevice struct {
	FriendlyName string
	Manufacturer string
	ModelName    string
	UDN          string
	DeviceType   string
	Services     []descriptionService
}

type descriptionService struct {
	ServiceType string
	ControlURL  string
}

// fetchDescription fetches and parses a UPnP device description XML.
func fetchDescription(ctx context.Context, location string) (*descriptionDevice, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, location, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", AppName+"/"+Version+" UPnP/1.1")
	client := &http.Client{Timeout: 4 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 65536))
	if err != nil {
		return nil, err
	}
	return parseDescriptionXML(body)
}

// parseDescriptionXML parses a UPnP device description XML.
// Uses a simple streaming approach — only reads the top-level <device>,
// ignoring embedded <deviceList> children.
func parseDescriptionXML(data []byte) (*descriptionDevice, error) {
	decoder := xml.NewDecoder(strings.NewReader(string(data)))
	dev := &descriptionDevice{}
	var inDevice, inServiceList, inService bool
	var currentService descriptionService
	var currentText strings.Builder

	for {
		tok, err := decoder.Token()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}
		switch t := tok.(type) {
		case xml.StartElement:
			switch t.Name.Local {
			case "device":
				if !inDevice {
					inDevice = true
				}
			case "serviceList":
				if inDevice {
					inServiceList = true
				}
			case "service":
				if inServiceList {
					inService = true
					currentService = descriptionService{}
				}
			default:
				currentText.Reset()
			}
		case xml.EndElement:
			switch t.Name.Local {
			case "device":
				inDevice = false
			case "serviceList":
				inServiceList = false
			case "service":
				if inService && currentService.ServiceType != "" {
					dev.Services = append(dev.Services, currentService)
				}
				inService = false
			default:
				text := strings.TrimSpace(currentText.String())
				if inService {
					switch t.Name.Local {
					case "serviceType":
						currentService.ServiceType = text
					case "controlURL":
						currentService.ControlURL = text
					}
				} else if inDevice && !inServiceList {
					switch t.Name.Local {
					case "friendlyName":
						dev.FriendlyName = text
					case "manufacturer":
						dev.Manufacturer = text
					case "modelName":
						dev.ModelName = text
					case "UDN":
						dev.UDN = text
					case "deviceType":
						dev.DeviceType = text
					}
				}
			}
		case xml.CharData:
			currentText.Write(t)
		}
	}
	if dev.UDN == "" {
		return nil, fmt.Errorf("no UDN in description")
	}
	return dev, nil
}

// discoverDevices performs a full SSDP discovery cycle:
// searches for both MediaRenderer and AVTransport targets in parallel,
// deduplicates by LOCATION, fetches descriptions, and returns discovered devices.
func discoverDevices(ctx context.Context, timeout time.Duration) ([]Device, error) {
	ctx, cancel := context.WithTimeout(ctx, timeout+2*time.Second) // +2s for description fetches
	defer cancel()

	// Search both targets in parallel.
	var (
		wg         sync.WaitGroup
		mu         sync.Mutex
		allResp    []ssdpResponse
		searchErr  error
	)
	wg.Add(2)
	go func() {
		defer wg.Done()
		resp, err := msearch(ctx, ssdpTargetMediaRenderer, timeout)
		mu.Lock()
		allResp = append(allResp, resp...)
		if err != nil && searchErr == nil {
			searchErr = err
		}
		mu.Unlock()
	}()
	go func() {
		defer wg.Done()
		resp, err := msearch(ctx, ssdpTargetAVTransport, timeout)
		mu.Lock()
		allResp = append(allResp, resp...)
		if err != nil && searchErr == nil {
			searchErr = err
		}
		mu.Unlock()
	}()
	wg.Wait()

	// Deduplicate by LOCATION.
	seen := make(map[string]bool)
	var locations []string
	for _, r := range allResp {
		if r.Location != "" && !seen[r.Location] {
			seen[r.Location] = true
			locations = append(locations, r.Location)
		}
	}

	// Fetch descriptions concurrently.
	var (
		devMu    sync.Mutex
		devices  []Device
		fetchWg  sync.WaitGroup
	)
	for _, loc := range locations {
		fetchWg.Add(1)
		go func(location string) {
			defer fetchWg.Done()
			desc, err := fetchDescription(ctx, location)
			if err != nil {
				return
			}
			d := deviceFromDescription(desc, location)
			if d != nil {
				devMu.Lock()
				devices = append(devices, *d)
				devMu.Unlock()
			}
		}(loc)
	}
	fetchWg.Wait()

	return devices, nil
}

// deviceFromDescription converts a parsed description into a Device,
// resolving the AVTransport controlURL.
func deviceFromDescription(desc *descriptionDevice, location string) *Device {
	// Find the AVTransport service.
	var avt *descriptionService
	for i := range desc.Services {
		if strings.Contains(desc.Services[i].ServiceType, ":service:AVTransport:") {
			avt = &desc.Services[i]
			break
		}
	}
	if avt == nil {
		return nil // not a media renderer, or no AVTransport exposed
	}

	// Resolve controlURL (may be relative).
	controlURL, err := resolveURL(avt.ControlURL, location)
	if err != nil {
		return nil
	}

	name := desc.FriendlyName
	if name == "" {
		name = "Unknown Device"
	}

	return &Device{
		ID:                     desc.UDN,
		Name:                   name,
		Manufacturer:           desc.Manufacturer,
		ModelName:              desc.ModelName,
		Location:               location,
		Available:              true,
		AVTransportControlURL:  controlURL,
		AVTransportServiceType: avt.ServiceType,
	}
}

// resolveURL resolves a possibly-relative URL against a base location.
func resolveURL(raw, base string) (string, error) {
	u, err := url.Parse(raw)
	if err != nil {
		return "", err
	}
	baseURL, err := url.Parse(base)
	if err != nil {
		return "", err
	}
	return baseURL.ResolveReference(u).String(), nil
}
