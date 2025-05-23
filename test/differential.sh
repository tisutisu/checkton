#!/usr/bin/env bats

setup() {
    load 'test_helper/utils'
    common_setup

    if ! (git config --global user.name || git config --global user.email); then
        git config --global user.name "checkton-test"
        git config --global user.email "checkton-test@noreply.org"
    fi

    ORIGINAL_PATH=$PWD

    cp -r . "$BATS_TEST_TMPDIR/checkton"
    cd "$BATS_TEST_TMPDIR/checkton" || exit 1

    CHECKTON_DIFF_BASE=$(git rev-parse HEAD)
    export CHECKTON_DIFF_BASE

    export CHECKTON_INCLUDE_REGEX='^test/.*\.ya?ml$'
}

teardown() {
    cd "$ORIGINAL_PATH" || exit 1
    cp -r "$BATS_TEST_TMPDIR/checkton/test/resources/differential/." test/resources/differential
}

R=test/resources

differential_checkton() {
    rc=0
    differential-checkton.sh 2> "$BATS_TEST_TMPDIR/differential-checkton.err" || rc=$?
    if [ "$rc" -ne 0 ]; then
        cat "$BATS_TEST_TMPDIR/differential-checkton.err" >&2
    fi
    return $rc
}

test_differential_checkton() {
    local testcase_name=$1
    shift
    for patch in "$@"; do
        git am "$patch"
    done

    local expected_files_dir="$R/differential/$testcase_name"

    run differential_checkton
    local csdiff_output="$output"
    assert_output_file "$csdiff_output" "$expected_files_dir/csdiff.sarif"

    test_human_readable_files "$csdiff_output" "$expected_files_dir"
}

@test "report issues in new script" {
    test_differential_checkton new-script \
        "$R/patches/0001-Add-a-script-with-some-issues.patch"
}

@test "report only new issues in renamed file" {
    test_differential_checkton renamed \
        "$R/patches/0001-Add-a-script-with-some-issues.patch" \
        "$R/patches/0001-Rename-tektontask-to-cooltask.patch"
}

@test "with CHECKTON_FIND_RENAMES=false, report all issues in renamed file" {
    CHECKTON_FIND_RENAMES=false \
    test_differential_checkton undetected-rename \
        "$R/patches/0001-Add-a-script-with-some-issues.patch" \
        "$R/patches/0001-Rename-tektontask-to-cooltask.patch"
}

@test "report only new issues in copied file" {
    test_differential_checkton detected-copy \
        "$R/patches/0001-Add-a-script-with-some-issues.patch" \
        "$R/patches/0001-Copy-tektontask-to-cooltask.patch"
}

@test "with CHECKTON_FIND_COPIES=false, report all issues in copied file" {
    CHECKTON_FIND_COPIES=false \
    test_differential_checkton undetected-copy \
        "$R/patches/0001-Add-a-script-with-some-issues.patch" \
        "$R/patches/0001-Copy-tektontask-to-cooltask.patch"
}

@test "with CHECKTON_INCLUDE_REGEX=cooltask, check only cooltask.yaml" {
    CHECKTON_INCLUDE_REGEX=cooltask \
    test_differential_checkton include-pattern \
        "$R/patches/0001-Add-a-script-with-some-issues.patch" \
        "$R/patches/0001-Copy-tektontask-to-cooltask.patch"
}

@test "with CHECKTON_EXCLUDE_REGEX=cooltask, check only tektontask.yaml" {
    CHECKTON_EXCLUDE_REGEX=cooltask \
    test_differential_checkton exclude-pattern \
        "$R/patches/0001-Add-a-script-with-some-issues.patch" \
        "$R/patches/0001-Copy-tektontask-to-cooltask.patch"
}

@test "set old base commit, thus reporting all issues" {
    local first_commit
    first_commit=$(git rev-list --max-parents=0 HEAD)

    CHECKTON_DIFF_BASE=$first_commit \
    test_differential_checkton old-base
}

@test "set CHECKTON_DIFFERENTIAL=false, thus reporting all issues" {
    CHECKTON_DIFFERENTIAL=false \
    test_differential_checkton diff-disabled \
        "$R/patches/0001-Add-a-script-with-some-issues.patch"
}

@test "handling a new issue of the same type as one that's already present in the file" {
    test_differential_checkton new-issue-of-same-type \
        "$R/patches/0001-Add-another-unquoted-variable.patch"
}

@test "generating an empty SARIF when there are no files to check" {
    test_differential_checkton no-files-to-check
}

@test "generating an empty SARIF when there files to check but no new issues" {
    test_differential_checkton no-new-issues \
        "$R/patches/0001-Rename-tektontask-to-cooltask.patch"
}

@test "don't report issues already fixed in target branch but still present in source branch" {
    git am "$R/patches/0001-Add-another-unquoted-variable.patch"

    # the issue got fixed in the target branch
    git revert HEAD --no-edit
    local diff_base
    diff_base=$(git rev-parse HEAD)

    # but our source branch forked from a point before the issue was fixed
    git checkout HEAD^ -b source-branch
    git am "$R/patches/0001-Modify-without-introducing-issues.patch"

    CHECKTON_DIFF_BASE=$diff_base \
    test_differential_checkton dont-report-stale-issues
}
