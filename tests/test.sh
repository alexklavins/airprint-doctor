#!/bin/bash
#
# airprint-doctor tests: the parts that read and reshape text, checked
# against known answers. Needs no printer, so it runs anywhere, CI included.
#
# © 2026 Aleksandrs Kļaviņš · alexander.klavinsh@gmail.com
# MIT licence (see LICENSE)

cd "$(dirname "$0")/.." || exit 2
AIRPRINT_DOCTOR_SOURCED=1
# shellcheck source=airprint-doctor
. ./airprint-doctor

PASS=0
FAIL=0

same() {
	if [ "$2" = "$3" ]; then
		PASS=$((PASS + 1))
	else
		FAIL=$((FAIL + 1))
		printf 'FAIL %s\n  got:  %s\n  want: %s\n' "$1" "$2" "$3"
	fi
}

# --- clash tags come off, real names stay ---
same "canon tags and garbage" "$(strip_clash 'Canon MF645C (1a:2b:3c) (1a:2b:3c) (1a:2b:3c) (1 (1a (1a:2b:3c)')" "Canon MF645C"
same "one canon tag" "$(strip_clash 'Canon MF645C (1a:2b:3c)')" "Canon MF645C"
same "numbered tag" "$(strip_clash 'HP LaserJet M404 (2)')" "HP LaserJet M404"
same "hp brackets are part of the name" "$(strip_clash 'HP Color LaserJet Pro M478f-9f [ABAAA3]')" "HP Color LaserJet Pro M478f-9f [ABAAA3]"
same "words in brackets stay" "$(strip_clash 'Office printer (Kitchen)')" "Office printer (Kitchen)"
same "hex-looking word stays" "$(strip_clash 'Brother (Bad)')" "Brother (Bad)"
same "plain name" "$(strip_clash 'EPSON ET-2850 Series')" "EPSON ET-2850 Series"

# --- %20 and friends ---
same "urldecode" "$(urldecode 'Canon%20MF645C%20(1a%3A2b%3A3c)')" "Canon MF645C (1a:2b:3c)"

# --- what kind of link a queue uses ---
parse_uri 'dnssd://Canon%20MF645C%20(1a%3A2b%3A3c)._ipps._tcp.local./?uuid=1f2e3d4c-5b6a-11d8-8020-0a1b2c3d4e5f'
same "dnssd kind" "$LINK_KIND" bonjour
same "dnssd type" "$LINK_TYPE" _ipps._tcp
same "dnssd name" "$LINK_NAME" "Canon MF645C (1a:2b:3c)"
same "dnssd uuid lower case" "$LINK_UUID" 1f2e3d4c-5b6a-11d8-8020-0a1b2c3d4e5f

parse_uri 'ipp://HP%20LaserJet%20M404%20(2)._ipp._tcp.local./'
same "ipp bonjour kind" "$LINK_KIND" bonjour
same "ipp bonjour name" "$LINK_NAME" "HP LaserJet M404 (2)"

parse_uri 'ipps://Canon1a2b3c.local:10443/ipp/print'
same "hostname kind" "$LINK_KIND" hostname
same "hostname host" "$LINK_HOST" Canon1a2b3c.local
same "hostname port" "$LINK_PORT" 10443

parse_uri 'ipp://Canon1a2b3c.local./ipp/print'
same "hostname trailing dot" "$LINK_HOST" Canon1a2b3c.local

parse_uri 'ipp://192.168.1.50/ipp/print'
same "ip kind" "$LINK_KIND" ip
same "ip host" "$LINK_HOST" 192.168.1.50
same "ip no port" "$LINK_PORT" ""

parse_uri 'socket://192.168.1.60:9100'
same "socket ip" "$LINK_KIND" ip
same "socket port" "$LINK_PORT" 9100

parse_uri 'ipp://[fe80::1]:631/ipp/print'
same "ipv6 kind" "$LINK_KIND" ip
same "ipv6 host" "$LINK_HOST" fe80::1
same "ipv6 port" "$LINK_PORT" 631

parse_uri 'ipp://printer.office.example.com/ipp/print'
same "dns kind" "$LINK_KIND" dns

parse_uri 'usb://Canon/MF645C?serial=1234'
same "usb is local" "$LINK_KIND" local

# --- paper names ---
same "a4" "$(media_to_ppd iso_a4_210x297mm)" A4
same "letter" "$(media_to_ppd na_letter_8.5x11in)" Letter
same "unknown paper" "$(media_to_ppd custom_max_216x355.6mm)" ""

# --- language codes ---
yes_no() { if "$@"; then echo yes; else echo no; fi; }
same "en valid" "$(yes_no valid_language en)" yes
same "en-us valid" "$(yes_no valid_language en-us)" yes
same "en-space invalid" "$(yes_no valid_language 'en-  ')" no

# --- printer status words ---
same "jam" "$(plain_reason media-jam-error)" "paper jam"
same "toner low" "$(plain_reason toner-low-warning)" "toner or ink low"
same "unknown reason" "$(plain_reason spool-area-full)" "spool-area-full"

# --- reading driver files ---
same "default paper from file" "$(ppd_value tests/fixtures/letter-only.ppd DefaultPageSize)" Letter
same "letter-only has one size" "$(grep -c '^\*PageSize ' tests/fixtures/letter-only.ppd)" 1
same "good file has sizes" "$(grep -c '^\*PageSize ' tests/fixtures/a4-everywhere.ppd)" 5

# --- the printer's answer about itself ---
ATTRS=tests/fixtures/attrs-bad-language.txt
same "attr with spaces in type" "$(attr media-default)" iso_a4_210x297mm
same "attr dns-sd name" "$(attr printer-dns-sd-name)" "Canon MF645C (1a:2b:3c) (1a:2b:3c)"
same "bad tag caught" "$(yes_no valid_language "$(attr natural-language-configured)")" no

# --- finding a printer in the network list ---
FOUND=tests/fixtures/found.txt
same "by uuid, prefers ipps" "$(found_lines 1 1f2e3d4c-5b6a-11d8-8020-0a1b2c3d4e5f | pick_scheme ipps | cut -d'|' -f2)" "ipps://Canon1a2b3c.local:10443/ipp/print"
same "by uuid, prefers ipp" "$(found_lines 1 1f2e3d4c-5b6a-11d8-8020-0a1b2c3d4e5f | pick_scheme ipp | cut -d'|' -f2)" "ipp://Canon1a2b3c.local:631/ipp/print"
same "by host, any case" "$(found_lines 4 CANON1A2B3C.local | pick_scheme ipp | cut -d'|' -f2)" "ipp://Canon1a2b3c.local:631/ipp/print"
same "nothing found" "$(found_lines 1 nope | pick_scheme ipp)" ""

# --- report redaction ---
list_queues() { printf 'Kitchen_Printer\n'; }
same "redact ip" "$(printf 'at 192.168.1.50' | redact)" "at x.x.x.x"
same "redact mac tag" "$(printf '"Canon MF645C (1a:2b:3c)"' | redact)" '"Canon MF645C (xx:xx:xx)"'
same "redact host" "$(printf 'ipp://Canon1a2b3c.local:631/ipp/print' | redact)" "ipp://<printer>.local:631/ipp/print"
same "redact uuid" "$(printf 'uuid=1f2e3d4c-5b6a-11d8-8020-0a1b2c3d4e5f' | redact)" "uuid=<uuid>"
same "redact queue name" "$(printf 'Kitchen_Printer  (Canon)' | redact)" "printer-1  (Canon)"
same "redact home" "$(printf '%s/Library' "$HOME" | redact)" "~/Library"
list_queues() { printf 'Office\nOffice_2\n'; }
same "redact overlapping names" "$(printf 'Office and Office_2' | redact)" "printer-2 and printer-1"
same "redact underscored mac tag" "$(printf 'Canon_MF645C__1a_2b_3c_' | redact)" "Canon_MF645C__xx_xx_xx_"

# --- default printer check, with the Mac's settings faked ---
# The real commands are swapped for small stand-ins, so this runs without
# touching the settings of the Mac it runs on.
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/airprint-doctor-test.XXXXXX")
trap 'rm -rf "$SCRATCH"' EXIT
LOG="$SCRATCH/calls.log"
: >"$LOG"
BACKUP_ROOT="$SCRATCH/backups"
HOME="$SCRATCH/home"
mkdir -p "$HOME/.cups"
FAKE_USE_LAST=1
list_queues() { printf 'Canon_Home\n'; }
lpstat() { [ "$1" = -d ] && printf 'system default destination: Canon_Home\n'; }
lpoptions() { printf 'lpoptions %s\n' "$*" >>"$LOG"; }
defaults() {
	case "$1 $3" in
	"read UseLastPrinter") printf '%s\n' "$FAKE_USE_LAST" ;;
	"read LastUsedPrinters")
		printf '(\n    {\n        Network = "192.168.1.1";\n        PrinterID = "Canon_Home";\n    },\n'
		printf '    {\n        Network = "10.0.0.1";\n        PrinterID = "Old_Office_HP";\n    }\n)\n'
		;;
	write* | export*) printf 'defaults %s\n' "$*" >>"$LOG" ;;
	esac
}

MODE=check ASSUME_YES=0 PROBLEMS=0
out=$(check_default_printer)
case "$out" in *"Old_Office_HP"*) same "stale printer named" ok ok ;; *) same "stale printer named" "$out" "mentions Old_Office_HP" ;; esac
same "check mode changes nothing" "$(grep -c . "$LOG")" 0

MODE=fix ASSUME_YES=1 PROBLEMS=0 BACKUP_DIR=""
check_default_printer >/dev/null 2>&1
same "fix turns off Last Printer Used" "$(grep -c 'defaults write org.cups.PrintingPrefs UseLastPrinter -bool false' "$LOG")" 1
same "fix sets the default" "$(grep -c 'lpoptions -d Canon_Home' "$LOG")" 1
same "fix saves settings first" "$(grep -c 'defaults export org.cups.PrintingPrefs' "$LOG")" 1

FAKE_USE_LAST=0
: >"$LOG"
MODE=fix ASSUME_YES=1 PROBLEMS=0 BACKUP_DIR=""
same "fixed default reads as fine" "$(check_default_printer | grep -c 'Default printer: Canon_Home')" 1
same "fine default is left alone" "$(grep -c . "$LOG")" 0

# --yes must not apply optional changes (tips), only fixes for problems.
MODE=fix ASSUME_YES=1
IS_PROBLEM=0
same "--yes skips tips" "$(yes_no offer "optional thing" 2>/dev/null | tail -1)" no
IS_PROBLEM=1
same "--yes applies fixes" "$(yes_no offer "real fix" 2>/dev/null | tail -1)" yes

printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
