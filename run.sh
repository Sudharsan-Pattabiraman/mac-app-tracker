#!/usr/bin/env bash
# TikTik build-and-run script. No Xcode needed, only Apple's Command Line Tools.
#
#   ./run.sh              Build TikTik, install it to ~/Applications and launch it
#   ./run.sh test         Run the core logic checks
#   ./run.sh build        Build TikTik.app into ./build without installing
#   ./run.sh logs         Stream TikTik's log messages (Ctrl-C to stop)
#   ./run.sh dump         Print today's recorded intervals
#   ./run.sh diagnose     If TikTik quit by itself: recent log and the latest crash report
#   ./run.sh uninstall    Quit TikTik and remove it from ~/Applications
#
# Any other arguments are passed to the app, e.g. ./run.sh --sample-data
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="TikTik"
BUNDLE_ID="app.tiktik"
BUILD_DIR="build"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"
CERT_NAME="TikTik Local"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

step() { printf '\033[1m▸ %s\033[0m\n' "$*"; }
note() { printf '  %s\n' "$*"; }
warn() { printf '\033[33m! %s\033[0m\n' "$*"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

check_tools() {
  [[ "$(uname)" == "Darwin" ]] || fail "TikTik builds on macOS only."
  local major
  major="$(sw_vers -productVersion | cut -d. -f1)"
  (( major >= 14 )) || fail "TikTik needs macOS 14 Sonoma or later (this Mac has $(sw_vers -productVersion))."
  if ! command -v swift >/dev/null 2>&1 || ! swift --version >/dev/null 2>&1; then
    fail "Swift isn't installed. Run:  xcode-select --install   then run ./run.sh again."
  fi
}

# --- signing ---------------------------------------------------------------
# A stable self-signed identity keeps the app's signature identical across rebuilds,
# so macOS remembers the Chrome permission and the login item. Falls back to ad-hoc.

has_identity() {
  security find-identity -p codesigning "$LOGIN_KEYCHAIN" 2>/dev/null | grep -q "\"$CERT_NAME\""
}

create_identity() {
  step "Creating the \"$CERT_NAME\" code-signing certificate (one time only)"
  note "It lives in your login keychain. Remove it any time in Keychain Access."
  local tmp pass
  tmp="$(mktemp -d)"
  pass="$(/usr/bin/openssl rand -hex 12)"
  cat >"$tmp/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $CERT_NAME
[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -config "$tmp/cert.cnf" >/dev/null 2>&1 \
    && /usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
       -name "$CERT_NAME" -out "$tmp/identity.p12" -passout "pass:$pass" >/dev/null 2>&1 \
    && security import "$tmp/identity.p12" -k "$LOGIN_KEYCHAIN" -P "$pass" -T /usr/bin/codesign >/dev/null 2>&1
  local status=$?
  rm -rf "$tmp"
  return $status
}

sign_app() {
  local identity="-"
  if has_identity || create_identity; then
    identity="$CERT_NAME"
  else
    warn "Couldn't create the signing certificate; using ad-hoc signing instead."
    note "macOS may ask for Chrome access again after each update."
  fi
  step "Signing ($([[ $identity == "-" ]] && echo ad-hoc || echo "$identity"))"
  if [[ $identity != "-" ]]; then
    note "If macOS asks whether codesign may use the key, enter your login password and click Always Allow."
  fi
  if ! codesign --force --sign "$identity" --identifier "$BUNDLE_ID" "$APP_PATH" >/dev/null 2>&1; then
    if [[ $identity != "-" ]]; then
      warn "Signing with \"$CERT_NAME\" failed; using ad-hoc signing instead."
      codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_PATH" >/dev/null
    else
      fail "Code signing failed."
    fi
  fi
}

# --- build -----------------------------------------------------------------

build_app() {
  step "Building $APP_NAME (the first build downloads dependencies and takes a few minutes)"
  swift build -c release --product "$APP_NAME"
  local bin_dir
  bin_dir="$(swift build -c release --show-bin-path)"

  step "Packaging $APP_PATH"
  rm -rf "$APP_PATH"
  mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
  cp "$bin_dir/$APP_NAME" "$APP_PATH/Contents/MacOS/$APP_NAME"
  cp Support/Info.plist "$APP_PATH/Contents/Info.plist"
  cp -R Sources/TikTik/Resources/. "$APP_PATH/Contents/Resources/"
  sign_app
}

quit_running() {
  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
      sleep 0.3
    done
    pkill -x "$APP_NAME" 2>/dev/null || true
  fi
}

install_and_launch() {
  step "Installing to $INSTALL_DIR/$APP_NAME.app"
  quit_running
  mkdir -p "$INSTALL_DIR"
  rm -rf "$INSTALL_DIR/$APP_NAME.app"
  cp -R "$APP_PATH" "$INSTALL_DIR/"
  step "Launching $APP_NAME. Look for the hourglass in your menu bar."
  if (( $# > 0 )); then
    open "$INSTALL_DIR/$APP_NAME.app" --args "$@"
  else
    open "$INSTALL_DIR/$APP_NAME.app"
  fi
}

# --- commands --------------------------------------------------------------

case "${1:-}" in
  test)
    check_tools
    step "Running core checks"
    swift run TikTikChecks
    ;;
  build)
    check_tools
    build_app
    step "Built $APP_PATH"
    ;;
  logs)
    log stream --style compact --predicate 'subsystem == "app.tiktik"'
    ;;
  dump)
    [[ -x "$INSTALL_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME" ]] || fail "TikTik isn't installed yet. Run ./run.sh first."
    "$INSTALL_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME" --dump
    ;;
  diagnose)
    step "Is TikTik running?"
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then note "Yes (pid $(pgrep -x "$APP_NAME"))"; else note "No"; fi

    step "TikTik's log, last 2 days (launches, quits, sleep and wake)"
    log show --last 2d --style compact --predicate 'subsystem == "app.tiktik"' 2>/dev/null \
      | grep -v '^Timestamp' | tail -n 60 || true

    step "Latest crash report"
    report="$(ls -t "$HOME/Library/Logs/DiagnosticReports/"TikTik* "$HOME/Library/Logs/DiagnosticReports/Retired/"TikTik* 2>/dev/null | head -n 1 || true)"
    if [[ -z "$report" ]]; then
      note "None. macOS didn't record a crash, so TikTik was quit or killed rather than crashing."
    elif command -v python3 >/dev/null 2>&1; then
      python3 Support/crash_summary.py "$report"
    else
      head -c 4000 "$report"
    fi
    echo
    note "Copy everything above and send it to Claude."
    ;;
  uninstall)
    quit_running
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
    step "Removed $INSTALL_DIR/$APP_NAME.app (your data in ~/Library/Application Support/TikTik is kept)"
    ;;
  -h|--help|help)
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *)
    check_tools
    build_app
    install_and_launch "$@"
    ;;
esac
