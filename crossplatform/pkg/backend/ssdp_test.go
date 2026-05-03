package backend

import (
	"strings"
	"testing"
)

func TestParseSSDPResponse_Valid200(t *testing.T) {
	raw := "HTTP/1.1 200 OK\r\n" +
		"LOCATION: http://192.168.1.23:8008/description.xml\r\n" +
		"USN: uuid:abc-123::urn:schemas-upnp-org:device:MediaRenderer:1\r\n" +
		"ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n" +
		"SERVER: Linux/3.14 UPnP/1.0 DLNADOC/1.50\r\n" +
		"\r\n"
	resp, ok := parseSSDPResponse(raw)
	if !ok {
		t.Fatal("expected ok")
	}
	if resp.Location != "http://192.168.1.23:8008/description.xml" {
		t.Errorf("Location = %q", resp.Location)
	}
	if resp.USN != "uuid:abc-123::urn:schemas-upnp-org:device:MediaRenderer:1" {
		t.Errorf("USN = %q", resp.USN)
	}
	if resp.ST != "urn:schemas-upnp-org:device:MediaRenderer:1" {
		t.Errorf("ST = %q", resp.ST)
	}
}

func TestParseSSDPResponse_HTTP10(t *testing.T) {
	raw := "HTTP/1.0 200 OK\r\n" +
		"LOCATION: http://10.0.0.5:49152/description.xml\r\n" +
		"\r\n"
	resp, ok := parseSSDPResponse(raw)
	if !ok {
		t.Fatal("expected ok for HTTP/1.0")
	}
	if resp.Location != "http://10.0.0.5:49152/description.xml" {
		t.Errorf("Location = %q", resp.Location)
	}
}

func TestParseSSDPResponse_RejectNotify(t *testing.T) {
	raw := "NOTIFY * HTTP/1.1\r\n" +
		"LOCATION: http://192.168.1.23:8008/description.xml\r\n" +
		"\r\n"
	_, ok := parseSSDPResponse(raw)
	if ok {
		t.Fatal("expected NOTIFY to be rejected")
	}
}

func TestParseSSDPResponse_MissingLocation(t *testing.T) {
	raw := "HTTP/1.1 200 OK\r\n" +
		"USN: uuid:abc\r\n" +
		"\r\n"
	_, ok := parseSSDPResponse(raw)
	if ok {
		t.Fatal("expected reject without LOCATION")
	}
}

func TestParseDescriptionXML_Basic(t *testing.T) {
	xml := `<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <specVersion>
    <major>1</major>
    <minor>0</minor>
  </specVersion>
  <device>
    <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
    <friendlyName>Living Room TV</friendlyName>
    <manufacturer>Sony</manufacturer>
    <modelName>BRAVIA</modelName>
    <UDN>uuid:abc-123</UDN>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
        <serviceId>urn:upnp-org:serviceId:AVTransport</serviceId>
        <controlURL>/MediaRenderer/AVTransport/Control</controlURL>
        <eventSubURL>/MediaRenderer/AVTransport/Event</eventSubURL>
        <SCPDURL>/MediaRenderer/AVTransport/scpd.xml</SCPDURL>
      </service>
    </serviceList>
  </device>
</root>`
	dev, err := parseDescriptionXML([]byte(xml))
	if err != nil {
		t.Fatal(err)
	}
	if dev.FriendlyName != "Living Room TV" {
		t.Errorf("FriendlyName = %q", dev.FriendlyName)
	}
	if dev.Manufacturer != "Sony" {
		t.Errorf("Manufacturer = %q", dev.Manufacturer)
	}
	if dev.UDN != "uuid:abc-123" {
		t.Errorf("UDN = %q", dev.UDN)
	}
	if len(dev.Services) != 1 {
		t.Fatalf("expected 1 service, got %d", len(dev.Services))
	}
	if !strings.Contains(dev.Services[0].ServiceType, "AVTransport:1") {
		t.Errorf("ServiceType = %q", dev.Services[0].ServiceType)
	}
	if dev.Services[0].ControlURL != "/MediaRenderer/AVTransport/Control" {
		t.Errorf("ControlURL = %q", dev.Services[0].ControlURL)
	}
}

func TestParseDescriptionXML_MultipleServices(t *testing.T) {
	xml := `<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <device>
    <friendlyName>Bedroom Box</friendlyName>
    <UDN>uuid:def-456</UDN>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType>
        <controlURL>/cm/control</controlURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:AVTransport:2</serviceType>
        <controlURL>/avt/control</controlURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
        <controlURL>/rc/control</controlURL>
      </service>
    </serviceList>
  </device>
</root>`
	dev, err := parseDescriptionXML([]byte(xml))
	if err != nil {
		t.Fatal(err)
	}
	if len(dev.Services) != 3 {
		t.Fatalf("expected 3 services, got %d", len(dev.Services))
	}
	// AVTransport should be the second one with version :2.
	avt := dev.Services[1]
	if !strings.Contains(avt.ServiceType, "AVTransport:2") {
		t.Errorf("ServiceType = %q", avt.ServiceType)
	}
}

func TestParseDescriptionXML_NoUDN(t *testing.T) {
	xml := `<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <device>
    <friendlyName>No UDN Device</friendlyName>
  </device>
</root>`
	_, err := parseDescriptionXML([]byte(xml))
	if err == nil {
		t.Fatal("expected error for missing UDN")
	}
}

func TestDeviceFromDescription_NoAVTransport(t *testing.T) {
	desc := &descriptionDevice{
		FriendlyName: "Test",
		UDN:          "uuid:test",
		Services: []descriptionService{
			{ServiceType: "urn:schemas-upnp-org:service:ConnectionManager:1", ControlURL: "/cm"},
		},
	}
	d := deviceFromDescription(desc, "http://192.168.1.1:8008/desc.xml")
	if d != nil {
		t.Fatal("expected nil for device without AVTransport")
	}
}

func TestDeviceFromDescription_RelativeControlURL(t *testing.T) {
	desc := &descriptionDevice{
		FriendlyName: "Test TV",
		UDN:          "uuid:test",
		Services: []descriptionService{
			{ServiceType: "urn:schemas-upnp-org:service:AVTransport:1", ControlURL: "/avt/control"},
		},
	}
	d := deviceFromDescription(desc, "http://192.168.1.1:8008/description.xml")
	if d == nil {
		t.Fatal("expected device")
	}
	if d.AVTransportControlURL != "http://192.168.1.1:8008/avt/control" {
		t.Errorf("ControlURL = %q", d.AVTransportControlURL)
	}
	if d.AVTransportServiceType != "urn:schemas-upnp-org:service:AVTransport:1" {
		t.Errorf("ServiceType = %q", d.AVTransportServiceType)
	}
}

func TestDeviceFromDescription_AbsoluteControlURL(t *testing.T) {
	desc := &descriptionDevice{
		FriendlyName: "Test TV",
		UDN:          "uuid:test",
		Services: []descriptionService{
			{ServiceType: "urn:schemas-upnp-org:service:AVTransport:1", ControlURL: "http://192.168.1.1:1400/avt/control"},
		},
	}
	d := deviceFromDescription(desc, "http://192.168.1.1:8008/description.xml")
	if d == nil {
		t.Fatal("expected device")
	}
	if d.AVTransportControlURL != "http://192.168.1.1:1400/avt/control" {
		t.Errorf("ControlURL = %q", d.AVTransportControlURL)
	}
}
