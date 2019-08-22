#!/bin/bash
#
# Add users with roles to the sg_internal_users.yml

VER_ES_PLUGIN="6.1.0-21.0"
ES_PATH="/elasticsearch"
FILE="sgconfig/sg_internal_users.yml"

ROLE=$1
USER=$2
PASS=$3

main(){
  exit_if_duplicated

  ES_CONTAINER=`docker-compose -f ../docker-compose-build.yml ps|grep "elasticsearch_"|grep "Up"|awk -F' ' {'print $1'}`
  if [ -z $ES_CONTAINER ]; then
      err "Elasticsearch is not running :_O"
      exit 1
  fi

  hash=$(password_to_hash)

  SUFFIX=`date '+%Y-%m-%d_%H%M%S'`
  echo "cp $FILE sgconfig/sg_internal_users.yml.$SUFFIX"|sh

  add_user_with_hash $FILE $USER $hash

  if [ "$ROLE" == "admin" ]; then
    append_admin_role $FILE
  elif [ "$ROLE" == "user" ]; then
    append_user_role $FILE
  fi

  printf "\n>>> File generated at sgconfig/sg_internal_users.yml adding the user $USER\n\n"

  reload_search_guard
}

#######################################
# Exits if the user already exists
# Globals:
#   FILE
#   USER
# Arguments:
#   None
# Returns:
#   None
#######################################
exit_if_duplicated(){
  echo "grep $USER: $FILE > /dev/null"|sh
  if [ $? -eq 0 ]; then
    err "The user $USER already exists in the file $FILE. Please remove it manually before excuting the script"
    exit 1
  fi
}

#######################################
# Converts password into a hash using a Search Guard script in the container
# Globals:
#   ES_CONTAINER
#   ES_PATH
#   USER
#   PASS
# Arguments:
#   None
# Returns:
#   myhash
#######################################
password_to_hash(){
  echo "docker exec $ES_CONTAINER chmod +x $ES_PATH/plugins/search-guard-6/tools/hash.sh"|sh
  local myhash=`echo docker exec $ES_CONTAINER $ES_PATH/plugins/search-guard-6/tools/hash.sh -p $PASS|sh`

  if [ -z $myhash ]; then
      err "Something went wrong getting the has for the user $USER"
      exit 1
  fi

  echo "$myhash"
}

#######################################
# Append configuration snippet to file with the role needed to have an
#  admin user
# Arguments:
#   File name
# Returns:
#   None
#######################################
append_admin_role(){
cat <<EOT >> $1
  roles:
    - admin
EOT
}

#######################################
# Append configuration snippet to file with the roles needed to have a logged
#  kibana user
# Arguments:
#   File name
# Returns:
#   None
#######################################
append_user_role(){
cat <<EOT >> $1
  roles:
    - kibanauser
    - readall
EOT
}

#######################################
# Append configuration snippet to file with the user and hash
# Arguments:
#   File name
# Returns:
#   None
#######################################
add_user_with_hash() {
cat <<EOT >> $1
$2:
  hash: $3
EOT
}

err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2
}

#######################################
# Reload Search Guard configuration files by invoking a script inside the container
# Globals:
#   ES_CONTAINER
#   ES_PATH
# Arguments:
#   None
# Returns:
#   None
#######################################
reload_search_guard(){
  docker exec $ES_CONTAINER $ES_PATH/plugins/search-guard-6/tools/sgadmin.sh -cd $ES_PATH/plugins/search-guard-6/sgconfig -icl -nhnv -cacert $ES_PATH/config/root-ca.pem -cert $ES_PATH/config/kirk.pem -key $ES_PATH/config/kirk-key.pem
  if [ $? -eq 0 ]; then
    printf "\n>>> Search Guard permissions updated\n"
    printf "\n>>> Backup copy can be found at sgconfig/sg_internal_users.yml.$SUFFIX\n"
  else
    err "Search Guard permissions were not updated"
  fi
}


if [ $# -ne 3 ]
  then
    echo -e "Wrong arguments buddy..\n"
    echo -e "Usage: add_user.sh role user password\n"
    echo "arguments:"
    echo -e "  role\t\tdepending on the role to be created it can be: admin|user|kibana"
    echo -e "  user\t\tuser name"
    echo -e "  password\tplain text password to be encrypted"
    exit 0
fi

main
