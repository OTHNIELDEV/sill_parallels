#!/usr/bin/env bash
# sill 연기 시험 — 가짜 설치 ISO 로 VM 을 만들고 실제로 부팅해 UEFI · TPM · QMP · 종료 · 스냅숏을 확인한다.
# Mac: ./test/smoke.sh            (HVF)
# Linux: SILL_ACCEL=tcg SILL_ARCH=aarch64 ./test/smoke.sh   (Apple Silicon 경로 흉내 · qemu-system-arm · swtpm · xorriso 필요)
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/sill-smoke.XXXX")"
export SILL_HOME="$WORK/vms"
W="$HERE/sill"
fail() {
  echo "✗ $*" >&2
  local f
  for f in "$SILL_HOME"/*/qemu.log "$SILL_HOME"/*/swtpm.log; do
    [ -s "$f" ] && { echo "── $f" >&2; tail -n 20 "$f" >&2; }
  done
  exit 1
}
cleanup() { "$W" stop smoke --force >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT

mkdir -p "$WORK/iso"; echo test > "$WORK/iso/readme.txt"
if command -v hdiutil >/dev/null 2>&1; then hdiutil makehybrid -quiet -iso -joliet -o "$WORK/fake.iso" "$WORK/iso"
else xorriso -as mkisofs -quiet -J -o "$WORK/fake.iso" "$WORK/iso" 2>/dev/null; fi

"$W" doctor >/dev/null || fail "doctor"
"$W" create smoke --iso "$WORK/fake.iso" --ram 4 --disk 64 --user tester >/dev/null || fail "create"
"$W" create smoke2 --iso "$WORK/fake.iso" --ram 4 --disk 64 >/dev/null || fail "create 2"
p1="$(grep RDP_PORT "$SILL_HOME/smoke.sill/config.env")"; p2="$(grep RDP_PORT "$SILL_HOME/smoke2.sill/config.env")"
[ "$p1" != "$p2" ] || fail "RDP 포트 중복: $p1"
echo ✓ 생성 · 포트 분리

"$W" start smoke --background >/dev/null || fail "start"
sock="${SILL_RUN:-/tmp/sill-$(id -u)}/smoke/qmp.sock"
out=""
for _ in $(seq 1 30); do
  out="$({ printf '{"execute":"qmp_capabilities"}\n'; sleep 0.3; printf '{"execute":"query-status"}\n{"execute":"query-tpm"}\n'; sleep 1; } | nc -w 2 -U "$sock" 2>/dev/null || true)"
  case "$out" in *'"running": true'*) break ;; esac
  sleep 1
done
case "$out" in *'"running": true'*) echo "✓ 부팅 · QMP" ;; *) fail "QMP 응답 없음: $out" ;; esac
case "$out" in *'"tpm0"'*) echo "✓ TPM 2.0 연결" ;; *) fail "TPM 없음" ;; esac

"$W" stop smoke --force >/dev/null || fail "stop"
sleep 1
ls_out="$("$W" list)"
case "$ls_out" in *"smoke "*"꺼짐"*) ;; *) fail "종료 뒤 상태: $ls_out" ;; esac
echo ✓ 종료

"$W" snapshot smoke save s1 >/dev/null && "$W" snapshot smoke restore s1 >/dev/null || fail "snapshot"
"$W" set smoke disk 80 >/dev/null || fail "disk resize"
echo ✓ 스냅숏 · 디스크 늘리기
echo "모두 통과"
