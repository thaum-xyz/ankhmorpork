include ../../Makefile.common

NET_SNMP_URL := https://raw.githubusercontent.com/net-snmp/net-snmp/v5.9/mibs
IANA_IFTYPE_URL   := https://www.iana.org/assignments/ianaiftype-mib/ianaiftype-mib
MIBDIR = mibs

.PHONY:
mibs: mib-dir $(MIBDIR)/IANA-IFTYPE-MIB.txt $(MIBDIR)/.net-snmp

mib-dir:
	mkdir -p $(MIBDIR)

$(MIBDIR)/IANA-IFTYPE-MIB.txt: mib-dir
	@curl $(CURL_OPTS) -o $(MIBDIR)/IANA-IFTYPE-MIB.txt $(IANA_IFTYPE_URL)

$(MIBDIR)/.net-snmp: mib-dir
	@echo ">> Downloading NET-SNMP mibs"
	@curl $(CURL_OPTS) -o $(MIBDIR)/HCNUM-TC $(NET_SNMP_URL)/HCNUM-TC.txt
	@curl $(CURL_OPTS) -o $(MIBDIR)/HOST-RESOURCES-MIB $(NET_SNMP_URL)/HOST-RESOURCES-MIB.txt
	@curl $(CURL_OPTS) -o $(MIBDIR)/IF-MIB $(NET_SNMP_URL)/IF-MIB.txt
	@curl $(CURL_OPTS) -o $(MIBDIR)/INET-ADDRESS-MIB $(NET_SNMP_URL)/INET-ADDRESS-MIB.txt
	@curl $(CURL_OPTS) -o $(MIBDIR)/IPV6-TC $(NET_SNMP_URL)/IPV6-TC.txt
	@curl $(CURL_OPTS) -o $(MIBDIR)/NET-SNMP-MIB $(NET_SNMP_URL)/NET-SNMP-MIB.txt
	@curl $(CURL_OPTS) -o $(MIBDIR)/NET-SNMP-TC $(NET_SNMP_URL)/NET-SNMP-TC.txt
	@curl $(CURL_OPTS) -o $(MIBDIR)/SNMP-FRAMEWORK-MIB $(NET_SNMP_URL)/SNMP-FRAMEWORK-MIB.txt
	@curl $(CURL_OPTS) -o $(MIBDIR)/SNMPv2-MIB $(NET_SNMP_URL)/SNMPv2-MIB.txt
	@curl $(CURL_OPTS) -o $(MIBDIR)/SNMPv2-SMI $(NET_SNMP_URL)/SNMPv2-SMI.txt
	@curl $(CURL_OPTS) -o $(MIBDIR)/SNMPv2-TC $(NET_SNMP_URL)/SNMPv2-TC.txt
	@curl $(CURL_OPTS) -o $(MIBDIR)/UCD-SNMP-MIB $(NET_SNMP_URL)/UCD-SNMP-MIB.txt
	@touch $(MIBDIR)/.net-snmp

$(MIBDIR)/NAS.mib: $(MIBDIR)/.net-snmp
	@echo "Download file from QNAP to continue"

snmp.yml: $(MIBDIR)/NAS.mib
	docker run -ti -v "$(PWD):/opt/" prom/snmp-generator generate


