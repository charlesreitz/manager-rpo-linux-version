#!/bin/bash

# CHARLES REITZ - 07/07/2024
# charles.reitz@totvs.com.br
# Script to automate tasks for the TOTVS Microsiga Protheus system, including:
# - Hot swap of RPO by specifying an RPO source
# - Applying multiple patches from a specific folder

# CONFIGURATION VARIABLES
# Update these variables based on your environment
SCRIPT_DIR="$(dirname "$0")"
INI_FILE="$SCRIPT_DIR/managerrpo.ini"

function get_ini_value() {
    awk -F '=' -v section="$1" -v key="$2" '
    /^\[/{gsub(/[][]/, "", $0); section_found = ($0 == section)}
    section_found && $1 == key {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}
    ' "$INI_FILE"
    echo $awk
}

# Function to update or add values in INI files
# Função para alterar um arquivo .ini
alterar_ini() {
     ini_file="$1"
    section="$2"
    key="$3"
    new_value="$4"
    temp_file="${ini_file}.tmp"

    # Flag to indicate if the key was found and updated
    key_updated=0

    # Loop through the ini file
    while IFS= read -r line; do
        # Check if the current line matches the section header
        if [[ "$line" =~ ^\[$section\] ]]; then
            echo "$line" >> "$temp_file"
            # Flag to start updating key-value pairs in this section
            in_section=1
            continue
        fi

        # Check if we are inside the desired section
        if [ $in_section ]; then
            # Check if the line starts with the desired key
            if [[ "$line" =~ ^$key[[:space:]]*=[[:space:]]* ]]; then
                # Update the key's value
                echo "$key=$new_value" >> "$temp_file"
                key_updated=1
            else
                echo "$line" >> "$temp_file"
            fi

            # Check if we reached the end of the section
            if [[ "$line" =~ ^$ ]]; then
                unset in_section
            fi
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$ini_file"

    # Check if the key was updated
    if [ $key_updated -eq 1 ]; then
        # Replace the original ini file with the temp file
        mv "$temp_file" "$ini_file"
        echo "Atualizado '$key' na sessao '$section' para '$new_value' no arquivo  '$ini_file'."
    else
        rm "$temp_file"
        echo "Erro: chave '$key' nao localizada na sessao '$section' no arquivo  '$ini_file'."
    fi
}



# Function to change RPO file
function change_rpo_file() {


    # Load INI file configurations
    cDataAtual=$(date +"%Y%m%d_%H%M%S")
    cFolderBak="bak_appserver_ini"
    cPathProtheus=$(get_ini_value "ambiente" "pathprotheus")
    cPathProtheusRemoto=$(get_ini_value "ambiente" "pathprotheusRemoto")
    cPathRPO=$(get_ini_value "ambiente" "pathrpo")
    cPathAtualizaRPO=$(get_ini_value "ambiente" "pathatualizarpo")
    cPathBinarios=$(get_ini_value "ambiente" "pathbinarios")
    rponamecustom=$(get_ini_value "ambiente" "rponamecustom")
    rponamedefault=$(get_ini_value "ambiente" "rponamedefault")

    pathrpocustom=$(get_ini_value "ambiente" "pathrpocustom")
    pathrpodefault=$(get_ini_value "ambiente" "pathrpodefault")


    IFS=',' read -r -a aAppservers <<< "$(get_ini_value "ambiente" "appservers")"
    cEnvironment=$(get_ini_value "ambiente" "environment")
    cPathBinarioDefrag=$(get_ini_value "ambiente" "binariodefrag")

    cAppserverNameFile="appserver"
    cAppserverIniFile="${cAppserverNameFile}.ini"
    logfile="${SCRIPT_DIR}\managerRPO.log"



    if [ "$cTipoTrocaDoRpo" = "custom" ]; then
        cRPODestPath="${cPathRPO}/${cEnvironment}/$cTipoTrocaDoRpo/$cDataAtual"
        cRPODestPathWithFileName=${cRPODestPath}/${rponamecustom}
        cRPOOrigem="${cPathAtualizaRPO}/${rponamecustom}"
        cRPONewFileAPO=${cRPODestPathWithFileName}
        if [[ ! -f "${cRPOOrigem}" ]]; then
            echo "RPO de origem (custom) não localizado: $cRPOOrigem"
            return 1
        fi


    else
        cRPODestPath="${cPathRPO}/${cEnvironment}/$cTipoTrocaDoRpo/$cDataAtual"
        cRPODestPathWithFileName=${cRPODestPath}/${rponamedefault}
        cRPOOrigem="${cPathAtualizaRPO}/${rponamedefault}"
        cRPONewFileAPO=${cRPODestPath}

        if [[ ! -f "${cRPOOrigem}" ]]; then
            echo "RPO de origem (default) não localizado: $cRPOOrigem"
            return 1
        fi

    fi
        
   # echo "Criando nova pasta $cRPODestPath"
    mkdir -p "$cRPODestPath"
    cp "$cRPOOrigem" "$cRPODestPathWithFileName"
   

    #echo "Verificando se o arquivo foi copiado $cRPODestPathWithFileName"
    if [[ ! -f "$cRPODestPathWithFileName" ]]; then
        echo "RPO destino não localizado: $cRPODestPathWithFileName"
        return 1
    fi

    #if [[ -d "$cRPODestPathRemoto" && ! -d "$cRPODestPathRemoto" ]]; then
    #    echo "RPO remoto nao localizado: $cRPODestPathRemoto"
     #   return 1
    #fi
   

    for appserver in "${aAppservers[@]}"; do

         if [ ! -d "${cPathProtheus}${cPathBinarios}/${appserver}/${cFolderBak}" ]; then
            # If the folder does not exist, create it
            mkdir -p "${cPathProtheus}${cPathBinarios}/${appserver}/${cFolderBak}"
            #echo "Pasta criada: ${cPathProtheus}${cPathBinarios}/${appserver}/${cFolderBak}"
        fi
        cIniFile="${cPathProtheus}${cPathBinarios}/${appserver}/${cAppserverIniFile}"
        cIniFileBak="${cPathProtheus}${cPathBinarios}/${appserver}/${cFolderBak}/${cAppserverNameFile}.ini.${cDataAtual}.bak"
   

        #echo "Efetuado backup do arquivo INI: $cIniFileBak"
        cp "$cIniFile" "$cIniFileBak"
        if [[ ! -f "$cIniFileBak" ]]; then
            echo "Falha ao criar arquivo de backup: $cIniFileBak"
            return 1
        fi
        #echo "Atualizado INI para novo RPO"
 
        alterar_ini "$cIniFile" "$cEnvironment" "$cKeyINIRPO" "$cRPONewFileAPO"
    done

    # if [[ -d "$cRPODestPathRemoto" ]]; then
    #     cRPONewFileRemoto="${cRPODestPathRemoto}/${cRPONewFolder}"
    #     cRPONewFileCustomRemoto="${cRPONewFileRemoto}/${RPOName}"
    #     cRPONewFileAPORemoto="${cRPONewFileRemoto}/${RPOName}"
    #     mkdir -p "$cRPONewFileRemoto"
    #     cp "$cRPOOrigFile" "$cRPONewFileAPORemoto"
    #     if [[ ! -f "$cRPONewFileAPORemoto" ]]; then
    #         echo "Remote file not copied: $cRPONewFileAPORemoto"
    #         return 1
    #     fi
    #     for appserver in "${aAppservers[@]}"; do
    #         cIniFile="${cPathProtheusRemoto}${cPathBinarios}/${appserver}/${cAppserverIniFile}"
    #         cIniFileBak="${cPathProtheusRemoto}${cPathBinarios}/${appserver}/${cAppserverNameFile}_${cRPONewFolder}.bak"
    #         if [[ -f "$cIniFile" ]]; then
    #             echo "Backing up remote INI file: $cIniFileBak"
    #             cp "$cIniFile" "$cIniFileBak"
    #             if [[ ! -f "$cIniFileBak" ]]; then
    #                 echo "Failed to create remote INI backup: $cIniFileBak"
    #                 return 1
    #             fi
    #             echo "Updating remote INI file to point to new RPO: $cIniFile"
    #             declare -A kv_list=(["RPOCustom"]="$cRPONewFileCustomRemoto")
    #             set_or_add_ini_value "$cIniFile" "${kv_list[@]}"
    #         fi
    #     done
    # fi

    echo "$(date) | User:$(whoami) | Troca de RPO" >> "$logfile"
    echo -e "\e[1;32mSucesso!!! \e[0m"
    return 0
}


# Check if the parameter is provided
if [[ -z "$1" ]]; then
    echo "Informa qual RPO deseja trocar 'default' ou 'custom'"
    exit 1
fi

# Check if the parameter is valid
if [[ "$1" != "default" && "$1" != "custom" ]]; then
    echo "Não foi enviadoo o RPO que deseja trocar, informe 'default' ou 'custom'"
    exit 1
fi

cTipoTrocaDoRpo="$1"
if [ "$1" = 'custom' ]; then
    echo "Altrerando RPO customizado"
    cKeyINIRPO="rpocustom"
fi
if [ "$1" = 'default' ]; then
    echo "Alterando RPO padrão"
    cKeyINIRPO="sourcepath"
fi



change_rpo_file
