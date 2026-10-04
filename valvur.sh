#!/usr/bin/env bash
# Kontori runneri valvur. Kui kontori arvuti (kontor-runner agent) on maas, jääb
# repo muutuja KONTOR_RUNNER "on" peale ja GitHubi tööd ootavad runnerit, mida
# pole. See skript paneb siis muutuja kõigis repodes "off" ja saadab ootel tööd
# GitHubi masinatesse — sama, mida agent ise tühjendamisel teeb.
#
# Tegutseb, kui muutuja on mõnes repos "on" ja kas
#   a) ükski kontori runner pole üheski repos online ning muutuja on olnud "on"
#      vähemalt FRESH_MIN minutit (agent paneb selle "on" kohe pärast runnerite
#      käivitamist — värske "on" võib tähendada, et runnerid alles ühenduvad), või
#   b) mõnes repos ootab töö kontori runnerit üle STALE_MIN minuti ja selle repo
#      kontori runnereid pole online.
# Agent paneb muutuja ise uuesti "on", kui runnerid on tagasi (iga 10 min).
#
#   DRY_RUN=1 ./valvur.sh   ainult ütleb, mida teeks
set -euo pipefail

OWNER=${OWNER:-Laudur}
REPOS=(${REPOS:-Raamat CombatReady Kontor kontor-runner})
LABEL=${LABEL:-kontor}
VAR=${VAR:-KONTOR_RUNNER}
FRESH_MIN=${FRESH_MIN:-5}
STALE_MIN=${STALE_MIN:-10}
DRY_RUN=${DRY_RUN:-0}

now=$(date -u +%s)
age_min() { echo $(( (now - $(date -u -d "$1" +%s)) / 60 )); }

any_on=0; oldest_on=0; any_online=0; stale=()
declare -A online_in waiting_in
for r in "${REPOS[@]}"; do
  repo="$OWNER/$r"
  read -r value updated < <(gh api "repos/$repo/actions/variables/$VAR" --jq '"\(.value) \(.updated_at)"' 2>/dev/null || echo "off -")
  online=$(gh api "repos/$repo/actions/runners" --jq \
    "[.runners[] | select(.status == \"online\") | select(any(.labels[]; .name == \"$LABEL\"))] | length")
  online_in[$r]=$online
  [ "$online" -gt 0 ] && any_online=1

  # Ootel tööd, mis tahavad kontori runnerit: jooksu id ja kõige vanema ootaja vanus.
  waiting=""
  for id in $(gh api "repos/$repo/actions/runs?status=queued&per_page=50" --jq '.workflow_runs[].id'); do
    created=$(gh api "repos/$repo/actions/runs/$id/jobs" --jq \
      "[.jobs[] | select(.status == \"queued\") | select(.labels | index(\"$LABEL\")) | .created_at] | min // empty")
    [ -n "$created" ] && waiting+="$id:$(age_min "$created") "
  done
  waiting_in[$r]=$waiting

  age="-"
  if [ "$value" = on ]; then
    any_on=1; age=$(age_min "$updated")
    [ "$age" -gt "$oldest_on" ] && oldest_on=$age
    for w in $waiting; do
      [ "${w#*:}" -ge "$STALE_MIN" ] && [ "$online" -eq 0 ] && { stale+=("$r"); break; }
    done
  fi
  echo "$repo: $VAR=$value (${age} min), kontori runnereid online: $online, ootel: ${waiting:-ei ole}"
done

reason=""
if [ "$any_on" -eq 1 ] && [ "$any_online" -eq 0 ] && [ "$oldest_on" -ge "$FRESH_MIN" ]; then
  reason="ükski kontori runner pole online, muutuja on olnud 'on' $oldest_on min"
elif [ ${#stale[@]} -gt 0 ]; then
  reason="tööd ootavad kontori runnerit üle $STALE_MIN min: ${stale[*]}"
fi
if [ -z "$reason" ]; then
  echo "Korras — midagi pole vaja teha."
  exit 0
fi

echo "::warning::Kontori arvuti paistab maas olevat ($reason). Suunan tööd GitHubi."
[ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "**Suunasin tööd GitHubi:** $reason" >> "$GITHUB_STEP_SUMMARY"
run() { if [ "$DRY_RUN" = 1 ]; then echo "  (dry-run) $*"; else "$@"; fi; }

# Muutuja kõigis repodes korraga: agent juhib neid ühe masinana.
for r in "${REPOS[@]}"; do run gh variable set "$VAR" --body off -R "$OWNER/$r"; done

# Ootel tööd uuesti: uus katse loeb runs-on'i uuesti ja läheb GitHubi masinasse.
for r in "${REPOS[@]}"; do
  for w in ${waiting_in[$r]}; do
    id=${w%%:*}
    echo "$OWNER/$r: jooks $id uuesti GitHubis"
    run gh run cancel "$id" -R "$OWNER/$r"
    if [ "$DRY_RUN" != 1 ]; then
      for _ in $(seq 30); do
        [ "$(gh run view "$id" -R "$OWNER/$r" --json status --jq .status)" = completed ] && break
        sleep 2
      done
    fi
    run gh run rerun "$id" -R "$OWNER/$r"
  done
done
