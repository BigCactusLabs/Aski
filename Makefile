.PHONY: check check-fast format-check test test-without-video-deadlock test-video-deadlock test-fast test-snapshots test-media test-research test-artifacts docc research-check lifecycle-check bench regen-kernels regen-vectors audit-vectors regen-repo-map repo-map-check doctor release-preflight

check:
	just check

check-fast:
	just check-fast

format-check:
	just format-check

test:
	just test

test-without-video-deadlock:
	just test-without-video-deadlock

test-video-deadlock:
	just test-video-deadlock

test-fast:
	just test-fast

test-snapshots:
	just test-snapshots

test-media:
	just test-media

test-research:
	just test-research

test-artifacts:
	just test-artifacts

docc:
	just docc

research-check:
	just research-check

lifecycle-check:
	just lifecycle-check

bench:
	just bench

regen-kernels:
	just regen-kernels

regen-vectors:
	just regen-vectors

audit-vectors:
	just audit-vectors

regen-repo-map:
	just regen-repo-map

repo-map-check:
	just repo-map-check

doctor:
	just doctor

release-preflight:
	just release-preflight
