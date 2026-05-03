package backend

import (
	"bytes"
	"context"
	"encoding/xml"
	"fmt"
	"html"
	"io"
	"net/http"
	"strings"
	"time"
)

type DLNAClient struct {
	HTTPClient *http.Client
}

func (c *DLNAClient) Play(ctx context.Context, device Device, mediaURL string) error {
	_ = c.Stop(ctx, device)
	if err := c.call(ctx, device, "SetAVTransportURI", map[string]string{
		"CurrentURI":         mediaURL,
		"CurrentURIMetaData": "",
	}); err != nil {
		return err
	}
	return c.call(ctx, device, "Play", map[string]string{"Speed": "1"})
}

func (c *DLNAClient) Stop(ctx context.Context, device Device) error {
	return c.call(ctx, device, "Stop", map[string]string{})
}

func (c *DLNAClient) call(ctx context.Context, device Device, action string, args map[string]string) error {
	if device.AVTransportControlURL == "" {
		return nil
	}
	serviceType := device.AVTransportServiceType
	if serviceType == "" {
		serviceType = "urn:schemas-upnp-org:service:AVTransport:1"
	}
	body := soapEnvelope(serviceType, action, args)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, device.AVTransportControlURL, bytes.NewBufferString(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", `text/xml; charset="utf-8"`)
	req.Header.Set("SOAPACTION", fmt.Sprintf(`"%s#%s"`, serviceType, action))
	client := c.HTTPClient
	if client == nil {
		client = &http.Client{Timeout: 8 * time.Second}
	}
	res, err := client.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode >= 200 && res.StatusCode < 300 {
		return nil
	}
	detail, _ := io.ReadAll(io.LimitReader(res.Body, 4096))
	return fmt.Errorf("%s failed: HTTP %d %s", action, res.StatusCode, strings.TrimSpace(string(detail)))
}

func soapEnvelope(serviceType, action string, args map[string]string) string {
	var b strings.Builder
	b.WriteString(`<?xml version="1.0" encoding="utf-8"?>`)
	b.WriteString(`<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>`)
	b.WriteString(`<u:` + action + ` xmlns:u="` + html.EscapeString(serviceType) + `">`)
	b.WriteString(`<InstanceID>0</InstanceID>`)
	for k, v := range args {
		b.WriteString(`<` + k + `>` + html.EscapeString(v) + `</` + k + `>`)
	}
	b.WriteString(`</u:` + action + `></s:Body></s:Envelope>`)
	return b.String()
}

// DescriptionDevice is intentionally small; it supports future SSDP/device XML
// wiring and keeps Docker/manual devices on the same AVTransport model.
type DescriptionDevice struct {
	XMLName xml.Name `xml:"root"`
}
