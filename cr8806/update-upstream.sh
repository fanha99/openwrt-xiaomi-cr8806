#!/bin/sh
# Lay ban va loi moi nhat tu OpenWrt upstream (main) va rebase patch CR8806 len tren.
set -e
cd "$(dirname "$0")/.."
git fetch origin
git fetch hzyitc ath11k-smallbuffers
git rebase origin/main
echo "Xong. Neu PR #21495 (ath11k smallbuffers) da duoc merge vao upstream,"
echo "git se tu bo qua cac commit trung lap khi rebase."
