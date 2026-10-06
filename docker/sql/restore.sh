#!/usr/bin/env bash
set -euo pipefail

SQLHOST="${SQLHOST:-sqlserver}"
SQLUSER="${SQLUSER:-sa}"
SQLPASSWORD="${SQLPASSWORD:?SQLPASSWORD is required}"
SQLDATABASE="${SQLDATABASE:-CELL_CRAFT_BURDUBAI}"
BAK="${BAK_PATH:-/backup/db.bak}"

if [ -x /opt/mssql-tools18/bin/sqlcmd ]; then
  SQLCMD=/opt/mssql-tools18/bin/sqlcmd
elif [ -x /opt/mssql-tools/bin/sqlcmd ]; then
  SQLCMD=/opt/mssql-tools/bin/sqlcmd
else
  echo "sqlcmd not found"
  exit 1
fi

sql() {
  "$SQLCMD" -S "$SQLHOST" -U "$SQLUSER" -P "$SQLPASSWORD" -C -b -r 1 "$@"
}

echo "Waiting for SQL Server at ${SQLHOST}..."
ready=0
for _ in $(seq 1 90); do
  if sql -Q "SELECT 1" >/dev/null 2>&1; then
    ready=1
    echo "SQL Server is ready."
    break
  fi
  sleep 2
done
if [ "$ready" -ne 1 ]; then
  echo "SQL Server did not become ready in time."
  exit 1
fi

exists=$(sql -h-1 -W -Q "SET NOCOUNT ON; SELECT CASE WHEN DB_ID(N'${SQLDATABASE}') IS NULL THEN 0 ELSE 1 END" | tr -d '[:space:]')
if [ "$exists" = "1" ]; then
  echo "Database ${SQLDATABASE} already exists. Skipping restore."
  exit 0
fi

echo "Reading backup file list from ${BAK}..."
filelist=$(sql -s "|" -y 0 -Q "SET NOCOUNT ON; RESTORE FILELISTONLY FROM DISK = N'${BAK}'")

moves=""
data_i=0
log_i=0
while IFS='|' read -r logical _ type _; do
  logical=$(printf '%s' "$logical" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  type=$(printf '%s' "$type" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  logical_sql=${logical//\'/\'\'}
  case "$type" in
    D)
      data_i=$((data_i + 1))
      if [ "$data_i" -eq 1 ]; then
        dest="/var/opt/mssql/data/${SQLDATABASE}.mdf"
      else
        dest="/var/opt/mssql/data/${SQLDATABASE}_${data_i}.ndf"
      fi
      moves="${moves}, MOVE N'${logical_sql}' TO N'${dest}'"
      ;;
    L)
      log_i=$((log_i + 1))
      if [ "$log_i" -eq 1 ]; then
        dest="/var/opt/mssql/data/${SQLDATABASE}_log.ldf"
      else
        dest="/var/opt/mssql/data/${SQLDATABASE}_log_${log_i}.ldf"
      fi
      moves="${moves}, MOVE N'${logical_sql}' TO N'${dest}'"
      ;;
  esac
done <<< "$filelist"

if [ "$data_i" -eq 0 ] || [ "$log_i" -eq 0 ]; then
  echo "Could not read data and log files from the backup."
  printf '%s\n' "$filelist"
  exit 1
fi

echo "Restoring ${SQLDATABASE} (${data_i} data file(s), ${log_i} log file(s))..."
sql -Q "RESTORE DATABASE [${SQLDATABASE}] FROM DISK = N'${BAK}' WITH REPLACE${moves}, STATS = 10"
echo "Restore complete."
