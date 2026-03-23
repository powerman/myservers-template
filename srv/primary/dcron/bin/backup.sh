#!/bin/bash
tmpdir=$(mktemp -d /tmp/duplicity.XXXXXX)
rc=0
profiles=""

TIMEFORMAT='Backup time: %0lR'
time for f in /etc/duplicity/*.filelist; do
    profile="$(basename "$f" .filelist)"
    profile_rc=0
    /etc/duplicity/backup.sh "$profile" "$@" >"$tmpdir/$profile.log" 2>&1 || profile_rc=$? rc=$?
    echo "$profile_rc" >"$tmpdir/$profile.rc"
    profiles="${profiles:+$profiles }$profile"
done

# Write prometheus metrics for Netdata monitoring (failure won't affect backup).
export PROM_PREFIX="$tmpdir"
export PROM_PROFILES="$profiles"
PROM_RCLONE=$(rclone size "$(sed 's,^rclone://,,' /etc/duplicity/target)")
export PROM_RCLONE
dockerize -template /etc/duplicity/backup.prom.tmpl:/prom/backup.prom.tmp &&
    mv /prom/backup.prom.tmp /prom/backup.prom || true

dockerize -template /etc/duplicity/backup.report.tmpl:/dev/stdout

echo
for p in $profiles; do
    cat "$tmpdir/$p.log"
done

rm -f "$tmpdir"/*
rmdir "$tmpdir"
exit $rc
