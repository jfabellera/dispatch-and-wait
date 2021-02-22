function trigger_workflow {
  echo "Triggering ${INPUT_EVENT_TYPE} in ${INPUT_OWNER}/${INPUT_REPO}"

  last_runid=$(curl -s "https://api.github.com/repos/${INPUT_OWNER}/${INPUT_REPO}/actions/runs?event=repository_dispatch" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Authorization: Bearer ${INPUT_TOKEN}" | jq '.workflow_runs[0].run_number')

  resp=$(curl -X POST -s "https://api.github.com/repos/${INPUT_OWNER}/${INPUT_REPO}/dispatches" \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${INPUT_TOKEN}" \
    -d "{\"event_type\": \"${INPUT_EVENT_TYPE}\", \"client_payload\": ${INPUT_CLIENT_PAYLOAD} }")

  if [ -z "$resp" ]
  then
    sleep 2
  else
    echo "Workflow failed to trigger"
    echo "$resp"
    exit 1
  fi
}

function ensure_workflow {
  max_wait=${INPUT_CREATION_TIMEOUT:-10}
  stime=$(date +%s)
  while [ $(( `date +%s` - $stime )) -lt $max_wait ]
  do
    current_runid=$(curl -s "https://api.github.com/repos/${INPUT_OWNER}/${INPUT_REPO}/actions/runs?event=repository_dispatch" \
      -H "Accept: application/vnd.github.v3+json" \
      -H "Authorization: Bearer ${INPUT_TOKEN}" | jq '.workflow_runs[0].run_number')

    [ "$current_runid" = $last_runid ] || break
    sleep 2
  done

  if [ "$current_runid" = "$last_runid" ]; then
    >&2 echo "Dispatch failed after timeout! Check the dispatched job has the correct syntax."
    exit 1
  fi

  # Pick up the workflow which appeared first (quite precise)
  i=$(($current_runid - $last_runid - 1))
  while [ $i -ge 0 ]; do
    workflow_runid=$(curl -s "https://api.github.com/repos/${INPUT_OWNER}/${INPUT_REPO}/actions/runs?event=repository_dispatch" \
      -H "Accept: application/vnd.github.v3+json" \
      -H "Authorization: Bearer ${INPUT_TOKEN}" | jq ".workflow_runs[$i] | select(.run_number==$(($current_runid-$i))) | .id")

    i=$(($i - 1))
    [ -z "$workflow_runid" ] || break
  done

  echo "Workflow dispatched run id is: ${workflow_runid}"
}

function wait_on_workflow {
  stime=$(date +%s)
  conclusion="null"

  echo "Dispatched workflow run URL:"
  echo -n "==> "
  curl -s "https://api.github.com/repos/${INPUT_OWNER}/${INPUT_REPO}/actions/runs/${workflow_runid}" \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Authorization: Bearer ${INPUT_TOKEN}" | jq -r '.html_url'

  while [[ $conclusion == "null" ]]
  do
    rtime=$(( `date +%s` - $stime ))
    if [[ "$rtime" -ge "$INPUT_MAX_TIME" ]]
    then
      echo "Time limit exceeded"
      exit 1
    fi
    sleep $INPUT_WAIT_TIME
    conclusion=$(curl -s "https://api.github.com/repos/${INPUT_OWNER}/${INPUT_REPO}/actions/runs/${workflow_runid}" \
    	-H "Accept: application/vnd.github.v3+json" \
    	-H "Authorization: Bearer ${INPUT_TOKEN}" | jq -r '.conclusion')

    if [ "$conclusion" == "failure" ]; then
      break
    fi
  done

  if [[ $conclusion == "success" ]]
  then
    echo "Suceeded"
  else
    echo "Failed (conclusion: $conclusion)!"
    exit 1
  fi
}

function main {
  trigger_workflow
  ensure_workflow
  wait_on_workflow
}

main
