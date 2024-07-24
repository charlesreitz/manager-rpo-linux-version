#!/bin/bash

# CHARLES REITZ - 07/07/2024
# charles.reitz@totvs.com.br
# Script to automate tasks for the TOTVS Microsiga Protheus system, including:
# - Hot swap of RPO by specifying an RPO source
# - Applying multiple patches from a specific folder

# CONFIGURATION VARIABLES
# Update these variables based on your environment
# Definindo sequências de escape para cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

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
        echo "Atualizado '$key' na sessao '$section' para '$new_value'  arquivo  '$ini_file'."
        echo "$(date) | User:$(whoami) | Atualizado '$key' na sessao '$section' para '$new_value'  arquivo  '$ini_file'." >> "$logfile" 
    else
        rm "$temp_file"
        echo "Erro: chave '$key' nao localizada na sessao '$section'  arquivo  '$ini_file'."
        echo "$(date) | User:$(whoami) | Erro: chave '$key' nao localizada na sessao '$section'  arquivo  '$ini_file'." >> "$logfile" 
    fi
}



# Function to change RPO file
function change_rpo_file() {


    # Load INI file configurations
    cDataAtual=$(date +"%Y%m%d_%H%M%S")
    cFolderBak="bak_appserver_ini"
    #cPathProtheus=$(get_ini_value "ambiente" "pathprotheus")
    #cPathProtheusRemoto=$(get_ini_value "ambiente" "pathprotheusRemoto")
    cPathRPO=$(get_ini_value "ambiente" "pathrpo")
    cPathAtualizaRPO=$(get_ini_value "ambiente" "pathatualizarpo")
    cPathBinarios=$(get_ini_value "ambiente" "pathbinarios")
    rponamecustom=$(get_ini_value "ambiente" "rponamecustom")
    rponamedefault=$(get_ini_value "ambiente" "rponamedefault")
    ambienteatualizarpo=$(get_ini_value "ambiente" "ambienteatualizarpo")
    arquivoappserver_ini=$(get_ini_value "ambiente" "arquivoappserver_ini")
    arquivoappsrv_ini=$(get_ini_value "ambiente" "arquivoappsrv_ini")


    pathprotheusdefault=$(get_ini_value "ambiente" "pathprotheusdefault")


    IFS=',' read -r -a aAppservers <<< "$(get_ini_value "ambiente" "appservers")"
    IFS=',' read -r -a aPathprotheus <<< "$(get_ini_value "ambiente" "pathprotheus")"
    IFS=',' read -r -a aEnvironment <<< "$(get_ini_value "ambiente" "environment")"

    cPathBinarioDefrag=$(get_ini_value "ambiente" "binariodefrag")


    logfile="${SCRIPT_DIR}/managerrpo.log"



    for cEnvironment in "${aEnvironment[@]}"; do
    

        echo "Ambiente: ${cEnvironment}"
       # echo "Desfragmentando RPO"
        
        #cd $pathprotheusdefault$cPathBinarios
        #.$cPathBinarioDefrag -compile -defragrpo -env=$ambienteatualizarpo 

        for pathprotheus in "${aPathprotheus[@]}"; do
               
            if [ "$cTipoTrocaDoRpo" = "custom" ]; then
                cRPODestPath="${pathprotheus}${cPathRPO}/${cEnvironment}/$cTipoTrocaDoRpo/$cDataAtual"
                cRPODestPathWithFileName=${cRPODestPath}/${rponamecustom}
                cRPOOrigem="${cPathAtualizaRPO}/${rponamecustom}"
                cRPONewFileAPO="${pathprotheusdefault}${cPathRPO}/${cEnvironment}/$cTipoTrocaDoRpo/$cDataAtual"/${rponamecustom}
                if [[ ! -f "${cRPOOrigem}" ]]; then
                    echo "RPO de origem (custom) não localizado: $cRPOOrigem"
                    return 1
                fi


            else
                cRPODestPath=${pathprotheus}"${cPathRPO}/${cEnvironment}/$cTipoTrocaDoRpo/$cDataAtual"
                cRPODestPathWithFileName=${cRPODestPath}/${rponamedefault}
                cRPOOrigem="${cPathAtualizaRPO}/${rponamedefault}"
                cRPONewFileAPO=${pathprotheusdefault}"${cPathRPO}/${cEnvironment}/$cTipoTrocaDoRpo/$cDataAtual" 

                if [[ ! -f "${cRPOOrigem}" ]]; then
                    echo -e "${RED}RPO de origem (default) não localizado: $cRPOOrigem${NC}"
                    return 1
                fi

            fi

                
           # echo "Criando nova pasta $cRPODestPath"
            echo "Copiando novo RPO "$cRPOOrigem" "$cRPODestPathWithFileName""
            #echo $cRPODestPath
            mkdir -p "$cRPODestPath"

            cp "$cRPOOrigem" "$cRPODestPathWithFileName"
            
            #exit

            #echo "Verificando se o arquivo foi copiado $cRPODestPathWithFileName"
            if [[ ! -f "$cRPODestPathWithFileName" ]]; then
                echo -e "${RED}RPO destino não localizado: $cRPODestPathWithFileName${NC}"
                return 1
            fi

            for appserver in "${aAppservers[@]}"; do

                if  [ -d "${pathprotheus}${cPathBinarios}/${appserver}" ]; then

              
                    cAppserverIniFile="${arquivoappserver_ini}"
                    cIniFile="${pathprotheus}${cPathBinarios}/${appserver}/${cAppserverIniFile}"
               
                    #echo ${cIniFile}
                     if [ ! -f ${cIniFile} ]; then
                        #echo "O arquivo appserver.ini não existe. Procurando por appsrv*.ini..."
                        #echo ${pathprotheus}${cPathBinarios}/${appserver}/${arquivoappsrv_ini}
                        # Procura por arquivos que correspondem ao padrão appsrv*.ini
                        files=($(ls ${pathprotheus}${cPathBinarios}/${appserver}/${arquivoappsrv_ini} 2>/dev/null))

                        # Verifica se algum arquivo foi encontrado
                        if [ ${#files[@]} -gt 0 ]; then
                            if [ ${#files[@]} -eq 1 ]; then
                                #echo -e "${GREEN}O seguinte arquivo foi encontrado: ${files[0]}"
                                for file in "${files[@]}"; do
                                    #echo "$(basename $file)"
                                    cAppserverIniFile="$(basename $file)"
                                    cIniFile="${pathprotheus}${cPathBinarios}/${appserver}/${cAppserverIniFile}"
                                done

                            else
                                echo -e "${RED}Erro: Mais de um arquivo appsrv*.ini foi encontrado.${NC}"
                                echo -e "${RED}Arquivos encontrados: ${files[@]}${NC}"
                                exit 1
                            fi
                        else
                            echo -e "${RED}Nenhum arquivo appsrv*.ini foi encontrado.${NC}"
                        fi
                    fi

                    #echo "Efetuado backup do arquivo INI: $cIniFileBak"
                    cIniFileBak="${pathprotheus}${cPathBinarios}/${appserver}/${cFolderBak}/${cAppserverIniFile}.${cDataAtual}.bak"
                    
                    if [ ! -d "${pathprotheus}${cPathBinarios}/${appserver}/${cFolderBak}" ]; then
                        # If the folder does not exist, create it
                        mkdir -p "${pathprotheus}${cPathBinarios}/${appserver}/${cFolderBak}"
                        #echo "Pasta criada: ${cPathProtheus}${cPathBinarios}/${appserver}/${cFolderBak}"
                    fi

                    #echo "${cIniFile} apra ${cIniFileBak}"
                    cp "$cIniFile" "$cIniFileBak"
                    if [[ ! -f "$cIniFileBak" ]]; then
                        echo -e "${RED}Falha ao criar arquivo de backup: $cIniFileBak${NC}"
                        return 1
                    fi

                    #echo "Atualizado INI para novo RPO"
                    alterar_ini "$cIniFile" "$cEnvironment" "$cKeyINIRPO" "$cRPONewFileAPO"
                fi
            done

        done
    done

    echo "$(date) | User:$(whoami) | Troca de RPO - $cTipoTrocaDoRpo " >> "$logfile" 
    echo -e "\e[1;32mSucesso!!! \e[0m"
    return 0
}


# Check if the parameter is provided
if [[ -z "$1" ]]; then
    echo -e "${RED}Informa qual RPO deseja trocar 'default' ou 'custom'${NC}"
    exit 1
fi

# Check if the parameter is valid
if [[ "$1" != "default" && "$1" != "custom" ]]; then
    echo -e "${RED}Não foi enviadoo o RPO que deseja trocar, informe 'default' ou 'custom'${RED}"
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
