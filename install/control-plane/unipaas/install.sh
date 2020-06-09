#!/bin/bash

_DIR="$(cd "$(dirname "$0")" && pwd)"
_PWD="$(pwd)"
cd $_DIR

err_log=$_DIR/std.log

. ../../_libs/common.sh
. ../../_libs/distro.sh
. ../../_libs/dep_offline.sh

########################################
# 
########################################
dependencies () {
    sudo echo "" # Ask user for sudo password now

    dep_jq &>>$err_log &
    bussy_indicator "Dependency on \"jq\"..."
    log "\n"

    dep_curl &>>$err_log &
    bussy_indicator "Dependency on \"curl\"..."
    log "\n"

    dep_sshpass &>>$err_log &
    bussy_indicator "Dependency on \"sshpass\"..."
    log "\n"

    dep_docker &>>$err_log &
    bussy_indicator "Dependency on \"Docker CE\"..."
    sudo usermod -aG docker $USER
    log "\n"

    sudo systemctl enable docker > /dev/null 2>&1 
    sudo systemctl start docker > /dev/null 2>&1 

    sudo docker load --input ../../build/offline_files/docker_images/eclipse-mosquitto-1.6.tar &>>$err_log &
    bussy_indicator "Loading docker image eclipse-mosquitto..."
    log "\n"

    sudo docker load --input ../../build/offline_files/docker_images/keycloak-9.0.3.tar &>>$err_log &
    bussy_indicator "Loading docker image keycloak..."
    log "\n"

    sudo docker load --input ../../build/offline_files/docker_images/gitlab-ce-12.10.1-ce.0.tar &>>$err_log &
    bussy_indicator "Loading docker image gitlab-ce..."
    log "\n"

    sudo docker load --input ../../build/offline_files/docker_images/nginx-1.17.10-alpine.tar &>>$err_log &
    bussy_indicator "Loading docker image nginx..."
    log "\n"

    sudo docker load --input ../../build/offline_files/docker_images/registry-2.7.1.tar &>>$err_log &
    bussy_indicator "Loading docker image registry..."
    log "\n"

    sudo docker load --input ../../build/offline_files/docker_images/postgres-12.2-alpine.tar &>>$err_log &
    bussy_indicator "Loading docker image postgres..."
    log "\n"

    sudo docker load --input ../../build/offline_files/docker_images/node-12.16.2.tar &>>$err_log &
    bussy_indicator "Loading docker image node..."
    log "\n"

    sudo docker load --input ../../build/offline_files/docker_images/multipaas-api-0.9.tar &>>$err_log &
    bussy_indicator "Loading docker image multipaas-api..."
    log "\n"

    sudo docker load --input ../../build/offline_files/docker_images/multipaas-ctrl-0.9.tar &>>$err_log &
    bussy_indicator "Loading docker image multipaas-ctrl..."
    log "\n"
}

########################################
# 
########################################
collect_informations() {
    get_network_interface_ip IFACE LOCAL_IP

    log "\n"
    read_input "Specify a MultiPaaS master user email address:" MP_U
   
    log "\n"
    read_input "Specify a MultiPaaS master password:" MP_P
}

########################################
# 
########################################
configure_firewall() {
    if [ "$DISTRO" == "ubuntu" ]; then
        FW_INACTIVE=$(sudo ufw status verbose | grep "inactive")
        if [ "$FW_INACTIVE" == "" ]; then
            sudo ufw allow http
            sudo ufw allow https
        fi
    fi
    if [ "$DISTRO" == "redhat" ]; then
        if [[ `firewall-cmd --state` = running ]]; then
            sudo firewall-cmd --zone=public --permanent --add-service=http
            sudo firewall-cmd --zone=public --permanent --add-service=https
            sudo firewall-cmd --reload
        fi
    fi
}

########################################
# 
########################################
install_core_components() {
    BASE_FOLDER="$(dirname "$_DIR")"
    BASE_FOLDER="$(dirname "$BASE_FOLDER")"
    BASE_FOLDER="$(dirname "$BASE_FOLDER")"

    cd $BASE_FOLDER

    POSTGRES_PASSWORD="$MP_P"
    KEYCLOAK_PASSWORD="$MP_P"
    API_SYSADMIN_USER="$MP_U"
    API_SYSADMIN_PASSWORD="$MP_P"
    API_IP="$LOCAL_IP"

    function join_by { local IFS="$1"; shift; echo "$*"; }
    arrIN=(${LOCAL_IP//./ })
    IP_SUB="${arrIN[@]:(-1)}"
    unset 'arrIN[${#arrIN[@]}-1]'
    DHCP_MASK=$(join_by . "${arrIN[@]}")
    DHCP_RESERVED="[250,251,252,253,254,$IP_SUB]"
    POSTGRES_USER="postgres"
    NGINX_HOST_IP="$LOCAL_IP"
    DB_HOST="$LOCAL_IP"
    MOSQUITTO_IP="$LOCAL_IP"
    REGISTRY_IP="$LOCAL_IP"
    DB_PASS=$POSTGRES_PASSWORD

    mkdir -p $HOME/.multipaas/nginx/certs
    mkdir -p $HOME/.multipaas/nginx/certs/tenants
    mkdir -p $HOME/.multipaas/nginx/conf.d
    mkdir -p $HOME/.multipaas/nginx/letsencrypt
    mkdir -p $HOME/.multipaas/postgres/pg-init-scripts
    mkdir -p $HOME/.multipaas/gitlab

    mkdir -p $HOME/.multipaas/auth/registry
    mkdir -p $HOME/.multipaas/auth/nginx

    cp $BASE_FOLDER/install/control-plane/pg_resources/create-multiple-postgresql-databases.sh $HOME/.multipaas/postgres/pg-init-scripts
    cp $BASE_FOLDER/install/control-plane/nginx_resources/nginx.conf $HOME/.multipaas/nginx
    cp $BASE_FOLDER/install/control-plane/nginx_resources/registry.conf $HOME/.multipaas/nginx/conf.d
    cp $BASE_FOLDER/install/control-plane/nginx_resources/keycloak.conf $HOME/.multipaas/nginx/conf.d
    cp $BASE_FOLDER/install/control-plane/nginx_resources/gitlab.conf $HOME/.multipaas/nginx/conf.d
    touch $HOME/.multipaas/nginx/conf.d/default.conf
    touch $HOME/.multipaas/nginx/conf.d/tcp.conf
    mkdir -p $HOME/.multipaas/postgres/data
    mkdir -p $HOME/.multipaas/mosquitto/config
    mkdir -p $HOME/.multipaas/mosquitto/data
    mkdir -p $HOME/.multipaas/mosquitto/log

    mkdir -p $HOME/tmp

    sed -i "s/<MYCLOUD_API_HOST_PORT>/$API_IP:3030/g" $HOME/.multipaas/nginx/conf.d/registry.conf

    NGINX_CRT_FOLDER=$HOME/.multipaas/nginx/certs
    NGINX_USERS_CRT_FOLDER=$HOME/.multipaas/nginx/certs/tenants
    chmod a+rw $NGINX_USERS_CRT_FOLDER

    # Gitlab
    printf "FR\nGaronne\nToulouse\nmultipaas\nITLAB\nmultipaas.gitlab.com\nmultipaas@multipaas.com\n" | openssl req -newkey rsa:2048 -nodes -sha256 -x509 -days 365 \
        -keyout $NGINX_CRT_FOLDER/nginx-gitlab.key \
        -out $NGINX_CRT_FOLDER/nginx-gitlab.crt > /dev/null 2>&1
    # Registry
    printf "FR\nGaronne\nToulouse\nmultipaas\nITLAB\nmultipaas.registry.com\nmultipaas@multipaas.com\n" | openssl req -newkey rsa:2048 -nodes -sha256 -x509 -days 365 \
        -keyout $NGINX_CRT_FOLDER/docker-registry.key \
        -out $NGINX_CRT_FOLDER/docker-registry.crt > /dev/null 2>&1 
    printf "FR\nGaronne\nToulouse\nmultipaas\nITLAB\nregistry.multipaas.org\nmultipaas@multipaas.com\n" | openssl req -newkey rsa:2048 -nodes -sha256 -x509 -days 365 \
        -keyout $NGINX_CRT_FOLDER/nginx-registry.key \
        -out $NGINX_CRT_FOLDER/nginx-registry.crt > /dev/null 2>&1 
    # Keycloak
    cat <<EOT >> ssl.conf
[ req ]
distinguished_name	= req_distinguished_name
attributes		= req_attributes

[ req_distinguished_name ]
countryName			= Country Name (2 letter code)
countryName_min			= 2
countryName_max			= 2
stateOrProvinceName		= State or Province Name (full name)
localityName			= Locality Name (eg, city)
0.organizationName		= Organization Name (eg, company)
organizationalUnitName		= Organizational Unit Name (eg, section)
commonName			= Common Name (eg, fully qualified host name)
commonName_max			= 64
emailAddress			= Email Address
emailAddress_max		= 64

[ req_attributes ]
challengePassword		= A challenge password
challengePassword_min		= 4
challengePassword_max		= 20

req_extensions = v3_req

[ v3_req ]
# Extensions to add to a certificate request
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
EOT
    openssl genrsa -out \
        $NGINX_CRT_FOLDER/rootCA.key \
        4096 > /dev/null 2>&1
    openssl req -x509 -new -nodes \
        -key $NGINX_CRT_FOLDER/rootCA.key -sha256 -days 1024 \
        -out $NGINX_CRT_FOLDER/rootCA.crt \
        -subj /C=FR/ST=Garonne/L=Toulouse/O=multipaas/OU=ITLAB/CN=multipaas.keycloak.com/emailAddress=multipaas@multipaas.com > /dev/null 2>&1
    openssl genrsa \
        -out $NGINX_CRT_FOLDER/nginx-keycloak.key \
        2048 > /dev/null 2>&1
    openssl req -config ./ssl.conf -new \
        -key $NGINX_CRT_FOLDER/nginx-keycloak.key \
        -out $NGINX_CRT_FOLDER/nginx-keycloak.csr \
        -subj /C=FR/ST=Garonne/L=Toulouse/O=multipaas/OU=ITLAB/CN=multipaas.keycloak.com/emailAddress=multipaas@multipaas.com > /dev/null 2>&1
    openssl x509 -req \
        -in $NGINX_CRT_FOLDER/nginx-keycloak.csr \
        -CA $NGINX_CRT_FOLDER/rootCA.crt \
        -CAkey $NGINX_CRT_FOLDER/rootCA.key \
        -CAcreateserial \
        -out $NGINX_CRT_FOLDER/nginx-keycloak.crt \
        -days 500 -sha256 -extensions v3_req -extfile ssl.conf > /dev/null 2>&1

    echo "$API_IP multipaas.com multipaas.registry.com registry.multipaas.org multipaas.keycloak.com multipaas.gitlab.com multipaas.static.com" >> /etc/hosts

    DR_CRED=$(docker run --entrypoint htpasswd registry:2.7.1 -Bbn multipaas_master_user multipaas_master_pass)
    NR_CRED=$(docker run --entrypoint htpasswd registry:2.7.1 -bn multipaas_master_user multipaas_master_pass)

    cat > $HOME/.multipaas/auth/nginx/htpasswd << EOF
$DR_CRED
EOF

    cat > $HOME/.multipaas/auth/registry/htpasswd << EOF
$NR_CRED
EOF

    touch $HOME/.multipaas/mosquitto/log/mosquitto.log
    chmod o+w $HOME/.multipaas/mosquitto/log/mosquitto.log
    chown 1883:1883 $HOME/.multipaas/mosquitto/log -R






   
}

########################################
# 
########################################
setup_keycloak() {
    # Wait untill Keycloak is up and running
    log "Waiting for Keycloak to become available (this can take up to 2 minutes)\n"
    until $(curl -k --output /dev/null --silent --head --fail https://multipaas.keycloak.com/auth/admin/master/console); do
        printf '.'
        sleep 5
    done

    log "\n"
    log "\n"
    log "To finalyze the setup, do the following:\n"
    log "\n"
    log "  1. Add the following line to your '/etc/hosts' file: $LOCAL_IP multipaas.com multipaas.registry.com registry.multipaas.org multipaas.keycloak.com multipaas.gitlab.com multipaas.static.com\n"
    log "  2. Open a browser and go to '"
    warn "https://multipaas.keycloak.com/auth/admin/master/console/#/realms/master/clients"
    log "'\n"
    log "  3. Keycloak uses a self signed certificate, add an exception to your browser to access the website\n"
    log "  4. Login to the Keycloak Admin page with the credentials '"
    warn "admin/$MP_P"
    log "'\n"
    log "  3. From the 'Clients' section, click on the client 'master-realm'\n"
    log "  4. Change 'Access Type' value to 'confidential'\n"
    log "  5. Enable the boolean value 'Service Accounts Enabled'\n"
    log "  6. Set 'Valid Redirect URIs' value to '*'\n"
    log "  7. Save those changes (button at the bottom of the page)\n"
    log "  8. Go to the 'Service Account Roles' tab and add the role 'admin' to the 'Assigned Roles' box\n"
    log "  9. Click on tab 'Credentials'\n"
    log "  10. When ready, copy and paste the 'Secret' value into this terminal, then press enter:\n"
    log "\n"
    read_input "SECRET:" KEYCLOAK_SECRET
    while [[ "$KEYCLOAK_SECRET" == '' ]]; do
        read_input "\nInvalide answer, try again:" KEYCLOAK_SECRET
    done
    log "\n"

    # Get master token from Keycloak
    KC_TOKEN=$(curl -s -k -X POST \
        'https://multipaas.keycloak.com/auth/realms/master/protocol/openid-connect/token' \
        -H "Content-Type: application/x-www-form-urlencoded"  \
        -d "grant_type=client_credentials" \
        -d "client_id=master-realm" \
        -d "client_secret=$KEYCLOAK_SECRET" \
        -d "username=admin"  \
        -d "password=$MP_P" \
        -d "scope=openid" | jq -r '.access_token')

    # Create client for kubernetes
    curl -s -k --request POST \
        -H "Accept: application/json" \
        -H "Content-Type:application/json" \
        -H "Authorization: Bearer $KC_TOKEN" \
        -d '{"clientId": "kubernetes-cluster", "publicClient": true, "standardFlowEnabled": true, "directGrantsOnly": true, "redirectUris": ["*"], "protocolMappers": [{"name": "groups", "protocol": "openid-connect", "protocolMapper": "oidc-group-membership-mapper", "config": {"claim.name" : "groups", "full.path" : "true","id.token.claim" : "true", "access.token.claim" : "true", "userinfo.token.claim" : "true"}}]}' \
        https://multipaas.keycloak.com/auth/admin/realms/master/clients

    # Retrieve client UUID
    CLIENT_UUID=$(curl -s -k --request GET \
        -H "Accept: application/json" \
        -H "Content-Type:application/json" \
        -H "Authorization: Bearer $KC_TOKEN" \
        https://multipaas.keycloak.com/auth/admin/realms/master/clients?clientId=kubernetes-cluster | jq '.[0].id' | sed 's/[\"]//g')

    # Create mp base group for multipaas k8s clusters in Keycloak
    curl -s -k --request POST \
        -H "Accept: application/json" \
        -H "Content-Type:application/json" \
        -H "Authorization: Bearer $KC_TOKEN" \
        -d '{"name": "mp"}' \
        https://multipaas.keycloak.com/auth/admin/realms/master/groups

    # Create client roles in Keycloak
    curl -s -k --request POST \
        -H "Accept: application/json" \
        -H "Content-Type:application/json" \
        -H "Authorization: Bearer $KC_TOKEN" \
        --data '{"clientRole": true,"name": "mp-sysadmin"}' \
        https://multipaas.keycloak.com/auth/admin/realms/master/clients/$CLIENT_UUID/roles
    SYSADMIN_ROLE_UUID=$(curl -s -k --request GET \
        -H "Accept: application/json" \
        -H "Content-Type:application/json" \
        -H "Authorization: Bearer $KC_TOKEN" \
        https://multipaas.keycloak.com/auth/admin/realms/master/clients/$CLIENT_UUID/roles/mp-sysadmin | jq '.id' | sed 's/[\"]//g')

    # Update admin email and role
    ADMIN_U_ID=$(curl -s -k --request GET \
        -H "Accept: application/json" \
        -H "Content-Type:application/json" \
        -H "Authorization: Bearer $KC_TOKEN" \
        https://multipaas.keycloak.com/auth/admin/realms/master/users?username=admin | jq '.[0].id' | sed 's/[\"]//g')

    curl -s -k -X PUT \
        https://multipaas.keycloak.com/auth/admin/realms/master/users/$ADMIN_U_ID \
        -H "Content-Type: application/json"  \
        -H "Authorization: Bearer $KC_TOKEN" \
        -d '{"email": "'"$MP_U"'"}'

    curl -s -k --request POST \
        -H "Accept: application/json" \
        -H "Content-Type:application/json" \
        -H "Authorization: Bearer $KC_TOKEN" \
        --data '[{"name": "mp-sysadmin", "id": "'"$SYSADMIN_ROLE_UUID"'"}]' \
        https://multipaas.keycloak.com/auth/admin/realms/master/users/$ADMIN_U_ID/role-mappings/clients/$CLIENT_UUID

    # Login to MultiPaaS with sysadmin credentials
    MP_TOKEN=$(curl -s http://$LOCAL_IP:3030/authentication/ \
        -H 'Content-Type: application/json' \
        --data-binary '{ "strategy": "local", "email": "'"$MP_U"'", "password": "'"$MP_P"'" }' | jq -r '.accessToken')

    curl -s -k \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $MP_TOKEN" \
        -X POST \
        -d '{"key":"KEYCLOAK_SECRET","value":"'"$KEYCLOAK_SECRET"'"}' \
        http://$LOCAL_IP:3030/settings 2>&1 | log_error_sanitizer
}

########################################
# 
########################################
install_gitlab() {
    # Create client for gitlab
    KC_TOKEN=$(curl -s -k -X POST \
        'https://multipaas.keycloak.com/auth/realms/master/protocol/openid-connect/token' \
        -H "Content-Type: application/x-www-form-urlencoded"  \
        -d "grant_type=client_credentials" \
        -d "client_id=master-realm" \
        -d "client_secret=$KEYCLOAK_SECRET" \
        -d "username=admin"  \
        -d "password=$MP_P" \
        -d "scope=openid" | jq -r '.access_token')

    curl -s -k --request POST \
        -H "Accept: application/json" \
        -H "Content-Type:application/json" \
        -H "Authorization: Bearer $KC_TOKEN" \
        -d '{"clientId": "gitlab", "publicClient": true, "standardFlowEnabled": true, "directGrantsOnly": true, "redirectUris": ["*"], "publicClient": false, "bearerOnly": false}' \
        https://multipaas.keycloak.com/auth/admin/realms/master/clients

    sleep 2 # Make sure secret is generated

    GITLAB_CLIENT_UUID=$(curl -s -k --request GET \
        -H "Accept: application/json" \
        -H "Content-Type:application/json" \
        -H "Authorization: Bearer $KC_TOKEN" \
        https://multipaas.keycloak.com/auth/admin/realms/master/clients?clientId=gitlab | jq '.[0].id' | sed 's/[\"]//g')

    GITLAB_SECRET=$(curl -s -k --request GET \
        -H "Accept: application/json" \
        -H "Content-Type:application/json" \
        -H "Authorization: Bearer $KC_TOKEN" \
        https://multipaas.keycloak.com/auth/admin/realms/master/clients/$GITLAB_CLIENT_UUID/client-secret | jq '.value')
    GITLAB_SECRET=${GITLAB_SECRET:1:${#GITLAB_SECRET}-2}

    # Login to MultiPaaS with sysadmin credentials
    MP_TOKEN=$(curl -s http://$LOCAL_IP:3030/authentication/ \
        -H 'Content-Type: application/json' \
        --data-binary '{ "strategy": "local", "email": "'"$MP_U"'", "password": "'"$MP_P"'" }' | jq -r '.accessToken')

    curl -s -k \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $MP_TOKEN" \
        -X POST \
        -d '{"key":"KEYCLOAK_GITLAB_SECRET","value":"'"$GITLAB_SECRET"'"}' \
        http://$LOCAL_IP:3030/settings 2>&1 | log_error_sanitizer

    log "Installing and configuring GitLab"

    
    log "\n"
    return 0
}




                                                          
                                                          


########################################
# LOGIC...
########################################
/usr/bin/clear

base64 -d <<<"ICAgXyAgICBfICAgICAgIF8gX19fX18gICAgICAgICAgICAgX19fX18gICAgX19fX18gX19fX18gIAogIHwgfCAgfCB8ICAgICAoXykgIF9fIFwgICAgICAgICAgIC8gX19fX3wgIC8gX19fX3wgIF9fIFwgCiAgfCB8ICB8IHxfIF9fICBffCB8X18pIHxfIF8gIF9fIF98IChfX18gICB8IHwgICAgfCB8X18pIHwKICB8IHwgIHwgfCAnXyBcfCB8ICBfX18vIF9gIHwvIF9gIHxcX19fIFwgIHwgfCAgICB8ICBfX18vIAogIHwgfF9ffCB8IHwgfCB8IHwgfCAgfCAoX3wgfCAoX3wgfF9fX18pIHwgfCB8X19fX3wgfCAgICAgCiAgIFxfX19fL3xffCB8X3xffF98ICAgXF9fLF98XF9fLF98X19fX18vICAgXF9fX19ffF98ICAgICA="
log "\n\n"

# Figure out what distro we are running
distro

# Install dependencies
dependencies

# Collect info from user
collect_informations

# Configure firewall
# configure_firewall &>>$err_log

# Install the core components
install_core_components

sudo sed '/multipaas.com/d' /etc/hosts &>>$err_log
sudo -- sh -c "echo $LOCAL_IP multipaas.com multipaas.registry.com registry.multipaas.org multipaas.keycloak.com multipaas.gitlab.com multipaas.static.com multipaas.static.com >> /etc/hosts" &>>$err_log

# # Setup keycloak admin client
# setup_keycloak

# # Install gitlab
# install_gitlab

# AUTOSTART_FILE=/etc/systemd/system/multipaas.service
# if [ -f "$AUTOSTART_FILE" ]; then
#     success "Autostart service enabled, skipping...\n"
# else 
#     CURRENT_USER=$(id -u -n)
#     DOT_CFG_DIR=$HOME/.multipaas
#     mkdir -p $DOT_CFG_DIR

#     sudo cp ./startup_cp.sh $DOT_CFG_DIR/startup_cp.sh
#     sudo chmod +wx $DOT_CFG_DIR/startup_cp.sh
#     sudo sed -i "s/<BASE_FOLDER>/${BASE_FOLDER//\//\\/}/g" $DOT_CFG_DIR/startup_cp.sh

#     sudo cp ./multipaas.service $AUTOSTART_FILE
#     sudo sed -i "s/<USER>/$CURRENT_USER/g" $AUTOSTART_FILE
#     sudo sed -i "s/<DOT_CFG_DIR>/${DOT_CFG_DIR//\//\\/}/g" $AUTOSTART_FILE

#     sudo systemctl daemon-reload
#     sudo systemctl enable multipaas.service
#     sudo systemctl start multipaas.service
# fi

# Done
log "\n"
success "[DONE] MultiPaaS control-plane deployed successfully!\n"
warn "[INFO] If no domain name (DNS resolvable) is configured, on all machines that will interact with MultiPaaS, add the following entry to your /etc/hosts file:\n"
log " ==> $LOCAL_IP multipaas.com multipaas.registry.com registry.multipaas.org multipaas.keycloak.com multipaas.gitlab.com multipaas.static.com\n"
log "\n"

cd "$_PWD"