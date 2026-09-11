# Assertions and a throwaway git environment for the test suites. Sourced only.

tests_run=0
tests_failed=0

report_pass() {
    tests_run=$((tests_run + 1))
    printf '  ok    %s\n' "$1"
}

report_failure() {
    tests_run=$((tests_run + 1))
    tests_failed=$((tests_failed + 1))
    printf '  FAIL  %s\n' "$1"
    printf '%s\n' "$2" | sed 's/^/        /'
}

expect_contains() {
    case "$3" in
        *"$2"*) report_pass "$1" ;;
        *) report_failure "$1" "expected to contain: $2
actual:
$3" ;;
    esac
}

expect_absent() {
    case "$3" in
        *"$2"*) report_failure "$1" "expected not to contain: $2
actual:
$3" ;;
        *) report_pass "$1" ;;
    esac
}

expect_equal() {
    if [ "$2" = "$3" ]; then
        report_pass "$1"
    else
        report_failure "$1" "expected: $2
actual:   $3"
    fi
}

expect_empty() {
    if [ -z "$2" ]; then
        report_pass "$1"
    else
        report_failure "$1" "expected no output, got:
$2"
    fi
}

expect_success() {
    if [ "$2" -eq 0 ]; then
        report_pass "$1"
    else
        report_failure "$1" "exit status $2:
$3"
    fi
}

expect_failure() {
    if [ "$2" -ne 0 ]; then
        report_pass "$1"
    else
        report_failure "$1" "expected a non-zero exit status, output:
$3"
    fi
}

expect_file() {
    if [ -e "$2" ]; then
        report_pass "$1"
    else
        report_failure "$1" "missing: $2"
    fi
}

expect_no_file() {
    if [ -e "$2" ]; then
        report_failure "$1" "unexpected: $2"
    else
        report_pass "$1"
    fi
}

# Points HOME and the global git config at a temporary directory so tests
# never read or write the real machine's configuration.
sandbox_git() {
    SANDBOX=$(mktemp -d)
    trap 'rm -rf "$SANDBOX"' EXIT
    HOME="$SANDBOX/home"
    XDG_CONFIG_HOME="$HOME/.config"
    GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
    GIT_CONFIG_NOSYSTEM=1
    export HOME XDG_CONFIG_HOME GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM
    mkdir -p "$HOME"
    git config --global user.name "Test"
    git config --global user.email test@example.com
    git config --global init.defaultBranch main
}

finish() {
    printf '%s run, %s failed\n' "$tests_run" "$tests_failed"
    [ "$tests_failed" -eq 0 ]
}
