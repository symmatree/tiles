#!/bin/bash
# Copy IETF SNMP MIBs to snmp_exporter generator directory
# Run from net-snmp/mibs directory
# Usage: SNMP_EXPORTER_MIBS_DIR=/path/to/snmp_exporter/generator/mibs bash /path/to/copy-snmp-mibs.sh

set -euxo pipefail

if [ ! -d "$SNMP_EXPORTER_MIBS_DIR" ]; then
	echo "Error: SNMP_EXPORTER_MIBS_DIR does not exist: $SNMP_EXPORTER_MIBS_DIR"
	exit 1
fi

# DISMAN-EVENT-MIB - Event triggers and actions
cp DISMAN-EVENT-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# DISMAN-SCHEDULE-MIB - Scheduling SNMP set operations
cp DISMAN-SCHEDULE-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# HOST-RESOURCES-MIB - Host systems management (CPU, memory, disk)
cp HOST-RESOURCES-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# IF-MIB - Network interface sub-layers
cp IF-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# IP-FORWARD-MIB - CIDR multipath IP Routes
cp IP-FORWARD-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# IP-MIB - IP and ICMP management
cp IP-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# IPV6-ICMP-MIB - ICMPv6
cp IPV6-ICMP-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# IPV6-MIB - IPv6 protocol
cp IPV6-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# IPV6-TCP-MIB - TCP over IPv6
cp IPV6-TCP-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# IPV6-UDP-MIB - UDP over IPv6
cp IPV6-UDP-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# NET-SNMP-AGENT-MIB - Net-SNMP agent monitoring
cp NET-SNMP-AGENT-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# NET-SNMP-EXTEND-MIB - Net-SNMP agent extensions
cp NET-SNMP-EXTEND-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# NET-SNMP-VACM-MIB - Net-SNMP VACM extensions
cp NET-SNMP-VACM-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# NOTIFICATION-LOG-MIB - SNMP notification logging
cp NOTIFICATION-LOG-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# SNMP-COMMUNITY-MIB - SNMPv1/v2c/v3 coexistence
cp SNMP-COMMUNITY-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# SNMP-FRAMEWORK-MIB - SNMP management architecture
cp SNMP-FRAMEWORK-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# SNMP-MPD-MIB - Message Processing and Dispatching
cp SNMP-MPD-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# SNMP-USER-BASED-SM-MIB - SNMPv3 User-based Security Model
cp SNMP-USER-BASED-SM-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# SNMP-VIEW-BASED-ACM-MIB - View-based Access Control Model
cp SNMP-VIEW-BASED-ACM-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# SNMPv2-MIB - Core SNMP entities
cp SNMPv2-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# TCP-MIB - TCP implementation management
cp TCP-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# UCD-DISKIO-MIB - Disk I/O statistics
cp UCD-DISKIO-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# UCD-DLMOD-MIB - Dynamic loadable MIB modules
cp UCD-DLMOD-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# UCD-SNMP-MIB - Private UCD SNMP extensions
cp UCD-SNMP-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# UDP-MIB - UDP implementation management
cp UDP-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# === DEPENDENCY CLOSURE ===

# SNMPv2-SMI - Root object identifiers (dependency)
cp SNMPv2-SMI.txt "$SNMP_EXPORTER_MIBS_DIR/"

# SNMPv2-TC - Textual conventions for SMIv2 (dependency)
cp SNMPv2-TC.txt "$SNMP_EXPORTER_MIBS_DIR/"

# INET-ADDRESS-MIB - Internet address textual representations (dependency)
cp INET-ADDRESS-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# HCNUM-TC - High capacity number textual conventions (dependency)
cp HCNUM-TC.txt "$SNMP_EXPORTER_MIBS_DIR/"

# NET-SNMP-TC - Net-SNMP textual conventions (dependency)
cp NET-SNMP-TC.txt "$SNMP_EXPORTER_MIBS_DIR/"

# NET-SNMP-MIB - Net-SNMP MIB (dependency)
cp NET-SNMP-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# SNMP-TARGET-MIB - SNMP target management (dependency)
cp SNMP-TARGET-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# IPV6-TC - IPv6 textual conventions (dependency)
cp IPV6-TC.txt "$SNMP_EXPORTER_MIBS_DIR/"

# IANAifType-MIB - IANA interface types (dependency)
cp IANAifType-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

# IANA-RTPROTO-MIB - IANA routing protocol identifiers (dependency)
cp IANA-RTPROTO-MIB.txt "$SNMP_EXPORTER_MIBS_DIR/"

echo "Successfully copied all IETF SNMP MIBs and dependencies to $SNMP_EXPORTER_MIBS_DIR"
