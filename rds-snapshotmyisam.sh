#!/bin/bash

# ============================= #
# Copyright © 2017 kohei YAMADA
# ============================= #

export AWS_DEFAULT_REGION=ap-northeast-1

DATE=`date +%Y-%m-%d-%H-%M`

WORKDIR=`dirname $0`
PARAMS="$WORKDIR/rds-snapshotmyisam.json"
GENERATIONS=7

COUNT=0
while [ $COUNT -lt `jq '.Instance | length' $PARAMS` ]; do

  INSTANCE=`jq -r .Instance[$COUNT][].Endpoint $PARAMS | awk -F"." '{print $1}'`
  ENDPOINT=`jq -r .Instance[$COUNT][].Endpoint $PARAMS`
  USERNAME=`jq -r .Instance[$COUNT][].User $PARAMS`
  PASSWORD=`jq -r .Instance[$COUNT][].Password $PARAMS`

  echo ""
  echo "[$INSTANCE]"

  # Stop replication.
  echo "Stop replication..."
  mysql -h$ENDPOINT -u$USERNAME -p$PASSWORD -e "CALL mysql.rds_stop_replication;"
  if [ $? -eq 0 ]; then
    # Create snapshot.
    echo ""
    echo "Create snapshot..."
    aws rds create-db-snapshot --db-instance-identifier $INSTANCE --db-snapshot-identifier $INSTANCE-$DATE
    if [ $? -ne 0 ]; then
      echo "ERROR: Can't create DB snapshot."
    fi
    echo ""

    # Start replication.
    echo "Start replication..."
    mysql -h$ENDPOINT -u$USERNAME -p$PASSWORD -e "CALL mysql.rds_start_replication;" 
    if [ $? -ne 0 ]; then
      echo "ERROR: Can't start replication."
      exit 1
    fi
  fi
  echo ""

  # Check generations.
  while [ $GENERATIONS -lt `aws rds describe-db-snapshots --db-instance-identifier $INSTANCE --snapshot-type manual | jq -r .DBSnapshots[].DBSnapshotIdentifier | grep -E $INSTANCE-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2} | wc -l` ]
  do
    NUM=`expr $GENERATIONS + 1`
    TARGET=`aws rds describe-db-snapshots --db-instance-identifier $INSTANCE --snapshot-type manual | jq -r .DBSnapshots[].DBSnapshotIdentifier | grep -E $INSTANCE-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2} | sort -r | sed -n ${NUM}p`

    # Delete old generations.
    aws rds delete-db-snapshot --db-snapshot-identifier $TARGET
    if [ $? -ne 0 ]; then
      echo "ERROR: Can't delete $TARGET."
      exit 1
    fi
  done
  echo ""

  echo "---------------------------------------------------------------------------------------------------"

  COUNT=$(( COUNT + 1 ))
done

echo "Backup completed."

