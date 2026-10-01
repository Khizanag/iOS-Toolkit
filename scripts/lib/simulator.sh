# Simulator resolution for scripts/ios-gate.sh. Sourced, not executed.
#
# Destinations are always passed to xcodebuild as `id=<UDID>`. A `name=`
# destination lets xcodebuild consider every device sharing a runtime-less name,
# and on a machine with several runtimes it has booted the wrong one: a test run
# that waited ten minutes for it, and a crash-looping Lock Screen behind it.

# Prints the UDID of the available simulator called exactly <name> on iOS
# <os> (e.g. 26.5). With an empty <os>, picks the newest runtime that has one.
# Prints nothing when there is no match.
resolve_simulator() {
    name=$1
    os=${2:-}
    xcrun simctl list devices available | awk -v want_name="$name" -v want_os="$os" '
        /^-- iOS / {
            runtime = $3
            next
        }
        /^-- / {
            runtime = ""
            next
        }
        runtime != "" {
            line = $0
            sub(/^ +/, "", line)
            if (match(line, / \([0-9A-F-]+\) \(/) == 0) next
            device = substr(line, 1, RSTART - 1)
            udid = substr(line, RSTART + 2, 36)
            if (device != want_name) next
            if (want_os != "" && runtime != want_os) next
            if (best == "" || newer(runtime, best_runtime)) {
                best = udid
                best_runtime = runtime
            }
        }
        function newer(a, b,    pa, pb, i, n) {
            n = split(a, pa, ".")
            split(b, pb, ".")
            for (i = 1; i <= n; i++) {
                if (pa[i] + 0 > pb[i] + 0) return 1
                if (pa[i] + 0 < pb[i] + 0) return 0
            }
            return 0
        }
        END {
            if (best != "") print best
        }
    '
}

# Creates a simulator called <name> of <device type> (e.g. "iPhone 17 Pro") on
# iOS <os> and prints its UDID. A per-app device keeps parallel sessions from
# sharing — and disturbing — one simulator's StoreKit and app state.
create_simulator() {
    runtime="com.apple.CoreSimulator.SimRuntime.iOS-$(printf '%s' "$3" | tr '.' '-')"
    xcrun simctl create "$1" "$2" "$runtime"
}
