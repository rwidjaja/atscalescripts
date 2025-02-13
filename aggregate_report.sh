#!/bin/bash

# Prompt for user input
read -p "Enter userid: " userid
read -s -p "Enter password: " password
echo
read -p "Enter hostname (e.g., https://ubuntu-atscale.atscaledomain.com): " hostname

# Fetch JWT token
export jwt=$(curl --insecure -X GET -u "$userid:$password" "$hostname:10500/default/auth")

# Fetch aggregate data
curl --insecure -H "Authorization: Bearer $jwt" \
-X GET -H 'Content-Type: application/json' \
-o aggregate_data.json \
"$hostname:10502/aggregates/orgId/default?limit=1000&status=active"

# Parse and print the required fields
jq -r '
  .response.data[] 
  | [.project_caption, .cube_caption, .connection_id, .name, .incremental, .type, .stats.average_build_duration, .stats.query_utilization, .latest_instance.table_name] 
  | @tsv' aggregate_data.json | 
awk -F'\t' '{
    printf "Project Caption: %s\nCube Caption: %s\nConnection ID: %s\nName: %s\nIncremental: %s\nType: %s\nAverage Build Duration: %s\nQuery Utilization: %s\nTable Name: %s\n\n", 
    $1, $2, $3, $4, $5, $6, $7, $8, $9
}' | 
awk '
BEGIN { FS="\n"; RS=""; OFS="\n" }
{
    print "Grouped by Project Caption: " $1
    print "Grouped by Cube Caption: " $2
    print $3, $4, $5, $6, $7, $8, $9, "\n"
}
'

calculate_query_saved_time() {
    local build_duration=$1
    local query_utilization=$2

    if (( $(echo "$query_utilization == 0" | bc -l) )); then
        echo "< 0h 0m 0.001s"
    else
        local saved_time=$(echo "scale=3; ($build_duration * $query_utilization) / 1000" | bc)
        if (( $(echo "$saved_time > 60" | bc -l) )); then
            saved_time=$(echo "scale=2; $saved_time / 60" | bc)
            echo "${saved_time} Minutes"
        else
            echo "${saved_time} Seconds"
        fi
    fi
}

# Parse JSON and format output
{
    echo -e "Project Caption\tCube Caption\tConnection ID\tName\tIncremental\tType\tAverage Build Duration (ms)\tQuery Utilization (%)\tTable Name\tQuery Saved Time"
    jq -r '
      .response.data[] 
      | [.project_caption, .cube_caption, .connection_id, .name, .incremental, .type, .stats.average_build_duration, .stats.query_utilization, .latest_instance.table_name] 
      | @tsv' aggregate_data.json | 
    while IFS=$'\t' read -r project_caption cube_caption connection_id name incremental type build_duration query_utilization table_name; do
        query_saved_time=$(calculate_query_saved_time "$build_duration" "$query_utilization")
        echo -e "$project_caption\t$cube_caption\t$connection_id\t$name\t$incremental\t$type\t$build_duration\t$query_utilization\t$table_name\t$query_saved_time"
    done
} | column -t -s $'\t'
