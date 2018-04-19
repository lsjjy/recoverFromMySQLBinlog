#!/bin/bash
#flashBack4MySQL.sh

#Script Description
#Recover data from insert / delete / update operations via binlog. Caution, the system variable binlog_format must be "ROW", and binlog_row_image must be "FULL".

#Command Line
#/bin/bash flashBack4MySQL.sh accessToMySQL databaseName tableName recoverFromInsert / recoverFromDelete / recoverFromUpdate fileName
#/bin/bash flashBack4MySQL.sh 'mysql -uroot -pxyz -S /tmp/mysql.sock' database table update update.txt

#How to get $fileName
#show binary logs;
#flush binary logs;

#mysqlbinlog -v -v --base64-output='decode-rows' --start-position=# | --start-datetime=name --stop-position | --stop-datetime=name binlogFileName > $fileName

#In fact, this script deals with the $fileName.
#

#
function usage {
  echo "usage:"
  echo -e "\t/bin/bash flashBack4MySQL.sh accessToMySQL databaseName tableName recoverFromInsert / recoverFromDelete / recoverFromUpdate fileName"

  echo -e "\n\teg. /bin/bash flashBack4MySQL.sh 'mysql -S /home/mysql_3306/mysql.sock' forbinlog tb1 insert insert.txt"
}

function modifyResultFile {
  local resultFile=$1
  local sqlFlag=$2
  local j
  local rows

  for((i=0; i<${#columnsArray[@]}; i++))
  do
    j=$((i+1))
    #sed -i "s/@${j}/${columnsArray[i]}/g" ${resultFile}
    sed -i "s/@${j}\b/${columnsArray[i]}/g" ${resultFile}
  done

  rows=$(grep -i "${sqlFlag}" ${resultFile} | sed -n "$=")
  echo -e "Recover, ${rows} rows.\nCheck ${resultFile} for details."
}

function recoverFromInsert {
  local fKeyFlag=$((keyFlag+1))
  local sKeyFlag=$((keyFlag+2))

  grep -A ${fKeyFlag} "INSERT INTO \`${databaseName}\`.\`${tableName}\`" ${fileName} \
  | sed -r -e 's/INSERT INTO/DELETE FROM/g' -e 's/SET/WHERE/g' -e '/^--/d' -e 's/### //g' -e 's#/\*.*\*/##g' \
  | sed '/@/{s/$/AND/}' \
  | awk -v AWK_sKeyFlag=$sKeyFlag '{if(NR % AWK_sKeyFlag == 0){gsub(" AND", ";", $0); print} else {print}}' \
  > recoverFromInsert.txt

  modifyResultFile "recoverFromInsert.txt" "DELETE"
}

function recoverFromDelete {
  local fKeyFlag=$((keyFlag+1))
  local sKeyFlag=$((keyFlag+2))

  grep -A ${fKeyFlag} "DELETE FROM \`${databaseName}\`.\`${tableName}\`" ${fileName} \
  | sed -e 's/DELETE FROM/INSERT INTO/g' -e 's/WHERE/SET/g' -e '/--/d' -e 's/### //g' -e 's# /.*/##g' -e 's/ (.*)//g' \
  | sed '/@/{s/$/,/g}' \
  | awk -v AWK_sKeyFlag=${sKeyFlag} '{if(NR % AWK_sKeyFlag == 0) {gsub(",", ";", $0); print} else {print}}' \
  > recoverFromDelete.txt

  modifyResultFile "recoverFromDelete.txt" "INSERT"
} 

function recoverFromUpdate {
  local fKeyFlag=$((keyFlag*2+2))

  local sKeyFlag=$((keyFlag+2))

  local tKeyFlag=$((keyFlag+3))
  local foKeyFlag=$((keyFlag*2+3))

  grep -A ${fKeyFlag} "UPDATE \`${databaseName}\`.\`${tableName}\`" ${fileName} \
  | sed -e 's/### WHERE/###-SET/' -e 's/### SET/###-WHERE/g' \
  | sed -e 's/### //g' -e 's/###-//g' -e '/--/d' -e 's# /.*/##g' \
  | sed '/@/{s/$/,/g}' \
  | awk -v AWK_sKeyFlag=${sKeyFlag} -v AWK_tKeyFlag=${tKeyFlag} -v AWK_foKeyFlag=${foKeyFlag} '{if(NR == AWK_sKeyFlag) {gsub(",", "", $0); print $0} else if(NR > AWK_tKeyFlag && NR < AWK_foKeyFlag) {gsub(",", " AND", $0); print} else if(NR == AWK_foKeyFlag) {gsub(",", ";", $0); NR = 0; print} else {print}}' \
  | sed ':a; /UPDATE/{N; s/\n/ /}; ta' \
  | sed -r 's/;[ \t]{0,}/\n/g' \
  | sed -r '/^[ \t]{0,}$/d' \
  | sed -r -e 's/[ \t]{1,}/ /g' -e 's/$/;/g' \
  | sed '1!G;h;$!d' \
  > recoverFromUpdate.txt

  modifyResultFile "recoverFromUpdate.txt" "UPDATE"
}

#main
test $# -eq 5 || { usage; exit 1; }

#parameters
accessToMySQL=$1
databaseName=$2
tableName=$3
recoverType=$4
fileName=$5

#file name
test -f "${fileName}" || { echo "${fileName} Not Exist."; exit 2; }

#binlog info
binlogInfo="${accessToMySQL} -e \"show variables like 'binlog_format'; show variables like 'binlog_row_image';\""

binlogFlag=$(eval ${binlogInfo} | awk '{if(NR % 2 == 0) {print $2}}' | sed ':a; N; s/\n/ /; ta')

test x"${binlogFlag}" = x"ROW FULL" || { echo "Binlog Format Error, exit ..."; exit 3; }

#columns details
cmd="${accessToMySQL} ${databaseName} -e 'show columns from ${tableName};'"

columnsArray=($(eval ${cmd} | awk '{if(NR > 1) {print $1}}' | sed ':a; N; s/\n/ /; ta'))

keyFlag=${#columnsArray[@]}

#recover type
case ${recoverType} in
"insert")
  recoverFromInsert
  ;;

"delete")
  recoverFromDelete
  ;;

"update")
  recoverFromUpdate
  ;;

*)
  usage
  ;;
esac

exit 0
