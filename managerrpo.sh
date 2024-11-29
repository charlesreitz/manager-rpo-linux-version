#!/bin/bash

# CHARLES REITZ - 07/07/2024
# charles.reitz@totvs.com.br
# Script para automatizar tarefas do sistema TOTVS Microsiga Protheus, incluindo:
# - Troca de RPO via SSH em servidores remotos
# - Aplicação de múltiplos patches de uma pasta específica

# VARIÁVEIS DE CONFIGURAÇÃO
# Definindo sequências de escape para cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # Sem Cor

SCRIPT_DIR="$(dirname "$0")"
INI_FILE="$SCRIPT_DIR/managerrpo.ini"

# Função para obter valores do arquivo INI
function get_ini_value() {
    awk -F '=' -v section="$1" -v key="$2" '
    /^\[/{gsub(/[][]/, "", $0); section_found = ($0 == section)}
    section_found && $1 == key {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}
    ' "$INI_FILE"
}

# Função para registrar logs com timestamp
log() {
    local message="$@"
    echo -e "$message"
    echo -e "$(date +"%Y-%m-%d %H:%M:%S") | $message" >> "$logfile"
}

# Função para executar comandos localmente ou via SSH
execute_command() {
    local host="$1"
    shift
    local cmd="$@"

    if [[ "$host" == "localhost" ]]; then
        eval "$cmd"
    else
        ssh "$host" "$cmd"
    fi
}

# Função para transferir arquivos localmente ou via SSH
transfer_file() {
    local src="$1"
    local dest="$2"
    local host="$3"

    if [[ "$host" == "localhost" ]]; then
        rsync -a "$src" "$dest"
    else
        rsync -e ssh -a "$src" "${host}:${dest}"
    fi
}

# Função para alterar ou adicionar valores em arquivos INI
alterar_ini() {
    local ini_file="$1"
    local section="$2"
    local key="$3"
    local new_value="$4"
    local host="$5"

    # Escapa caracteres especiais no new_value
    local new_value_escaped
    new_value_escaped=$(printf '%s' "$new_value" | sed 's/[&|]/\\&/g')

    # Captura o valor atual antes da alteração
    local old_value
    if [[ "$host" == "localhost" ]]; then
        if [[ -f "$ini_file" ]]; then
            old_value=$(grep -E "^\s*${key}\s*=" "$ini_file" | awk -F '=' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//')
        else
            old_value="N/A (Arquivo não existe)"
        fi
    else
        if ssh "$host" "test -f '$ini_file'"; then
            old_value=$(ssh "$host" "grep -E '^\s*${key}\s*=' '$ini_file' | awk -F '=' '{print \$2}' | sed 's/^[ \t]*//;s/[ \t]*\$//'" 2>/dev/null)
            if [[ -z "$old_value" ]]; then
                old_value="N/A (Chave não encontrada)"
            fi
        else
            old_value="N/A (Arquivo não existe)"
        fi
    fi

    # Use um delimitador alternativo (|) para evitar conflito com '/'
    local sed_script="/^\[$section\]/,/^\[/{s|^\($key\s*=\s*\).*|\1$new_value_escaped|}"

    if [[ "$host" == "localhost" ]]; then
        # Backup do arquivo INI se existir
        if [[ -f "$ini_file" ]]; then
            cp "$ini_file" "${ini_file}.bak"
        fi
        # Executa o sed localmente
        sed -i "$sed_script" "$ini_file"
        if [[ $? -eq 0 ]]; then
            log "${GREEN}Arquivo INI atualizado no host '${host}':${NC}"
            log "    Arquivo: ${ini_file}"
            log "    Seção: ${section}"
            log "    Chave: ${key}"
            log "    Valor Antigo: ${old_value}"
            log "    Valor Novo: ${new_value}"
        else
            log "${RED}Erro ao atualizar '$key' na sessão '$section' no arquivo '$ini_file'.${NC}"
        fi
    else
        # Cria um script remoto para backup e alteração
        local remote_backup="${ini_file}.bak"
        ssh "$host" "if [ -f '$ini_file' ]; then cp '$ini_file' '$remote_backup'; fi && sed -i '$sed_script' '$ini_file'"
        if [[ $? -eq 0 ]]; then
            log "${GREEN}Arquivo INI atualizado no host '${host}':${NC}"
            log "    Arquivo: ${ini_file}"
            log "    Seção: ${section}"
            log "    Chave: ${key}"
            log "    Valor Antigo: ${old_value}"
            log "    Valor Novo: ${new_value}"
        else
            log "${RED}Erro ao atualizar '$key' na sessão '$section' no arquivo '$ini_file' no host '$host'.${NC}"
        fi
    fi
}

# Função para mudar o arquivo RPO
function change_rpo_file() {

    # Carregar configurações do arquivo INI
    local cDataAtual=$(date +"%Y%m%d_%H%M%S")
    local cFolderBak="bak_appserver_ini"

    local cPathRPO=$(get_ini_value "ambiente" "pathrpo")
    local cPathAtualizaRPO=$(get_ini_value "ambiente" "pathatualizarpo")
    local cPathBinarios=$(get_ini_value "ambiente" "pathbinarios")
    local rponamecustom=$(get_ini_value "ambiente" "rponamecustom")
    local rponamedefault=$(get_ini_value "ambiente" "rponamedefault")
    local ambienteatualizarpo=$(get_ini_value "ambiente" "ambienteatualizarpo")
    local arquivoappserver_ini=$(get_ini_value "ambiente" "arquivoappserver_ini")
    local arquivoappsrv_ini=$(get_ini_value "ambiente" "arquivoappsrv_ini")

    local pathprotheusdefault=$(get_ini_value "ambiente" "pathprotheusdefault")

    IFS=',' read -r -a aAppservers <<< "$(get_ini_value "ambiente" "appservers")"
    IFS=',' read -r -a aPathprotheus <<< "$(get_ini_value "ambiente" "pathprotheus")"
    IFS=',' read -r -a aEnvironment <<< "$(get_ini_value "ambiente" "environment")"

    local cPathBinarioDefrag=$(get_ini_value "ambiente" "binariodefrag")

    local logfile="${SCRIPT_DIR}/managerrpo.log"

    for cEnvironment in "${aEnvironment[@]}"; do

        log "${BLUE}==========================================${NC}"
        log "${BLUE}Processando Ambiente: ${cEnvironment}${NC}"
        log "${BLUE}==========================================${NC}"

        for pathprotheus in "${aPathprotheus[@]}"; do

            # Determinar se o pathprotheus é remoto ou local
            if [[ "$pathprotheus" =~ ^/ ]]; then
                # Local
                host="localhost"
                base_path="$pathprotheus"
            else
                # Remoto: separa host e caminho
                host=$(echo "$pathprotheus" | cut -d'/' -f1)
                path=$(echo "$pathprotheus" | cut -d'/' -f2-)
                base_path="/$path" # Adiciona '/' ao caminho
            fi

            log "${YELLOW}Host: ${host}${NC}"
            log "${YELLOW}Base Path: ${base_path}${NC}"

            if [ "$cTipoTrocaDoRpo" = "custom" ]; then
                cRPODestPath="${base_path}${cPathRPO}/${cEnvironment}/$cTipoTrocaDoRpo/$cDataAtual"
                cRPODestPathWithFileName="${cRPODestPath}/${rponamecustom}"
                cRPOOrigem="${cPathAtualizaRPO}/${rponamecustom}"
                cRPONewFileAPO="${pathprotheusdefault}${cPathRPO}/${cEnvironment}/$cTipoTrocaDoRpo/$cDataAtual/${rponamecustom}"

                if [[ "$host" == "localhost" && ! -f "${cRPOOrigem}" ]]; then
                    log "${RED}RPO de origem (custom) não localizado: $cRPOOrigem${NC}"
                    continue
                fi

            else
                cRPODestPath="${base_path}${cPathRPO}/${cEnvironment}/$cTipoTrocaDoRpo/$cDataAtual"
                cRPODestPathWithFileName="${cRPODestPath}/${rponamedefault}"
                cRPOOrigem="${cPathAtualizaRPO}/${rponamedefault}"
                cRPONewFileAPO="${pathprotheusdefault}${cPathRPO}/${cEnvironment}/$cTipoTrocaDoRpo/$cDataAtual"

                if [[ "$host" == "localhost" && ! -f "${cRPOOrigem}" ]]; then
                    log "${RED}RPO de origem (default) não localizado: $cRPOOrigem${NC}"
                    continue
                fi
            fi

            log "${GREEN}Copiando novo RPO de '$cRPOOrigem' para '$cRPODestPathWithFileName' no host '$host'${NC}"

            # Criar o diretório de destino
            execute_command "$host" "mkdir -p '$cRPODestPath'"

            # Transferir o arquivo RPO
            transfer_file "$cRPOOrigem" "$cRPODestPathWithFileName" "$host"

            # Verificar se o arquivo foi copiado
            if [[ "$host" == "localhost" ]]; then
                if [[ ! -f "$cRPODestPathWithFileName" ]]; then
                    log "${RED}RPO destino não localizado: $cRPODestPathWithFileName${NC}"
                    continue
                fi
            else
                if ! ssh "$host" "test -f '$cRPODestPathWithFileName'"; then
                    log "${RED}RPO destino não localizado: $cRPODestPathWithFileName no host '$host'${NC}"
                    continue
                fi
            fi

            for appserver in "${aAppservers[@]}"; do

                appserver_dir="${base_path}${cPathBinarios}/${appserver}"

                # Verificar se o diretório do appserver existe
                if [[ "$host" == "localhost" ]]; then
                    if [ ! -d "$appserver_dir" ]; then
                        log "${YELLOW}Appserver '$appserver' não encontrado no host '$host'. Pulando...${NC}"
                        continue
                    fi
                else
                    if ! ssh "$host" "test -d '$appserver_dir'"; then
                        log "${YELLOW}Appserver '$appserver' não encontrado no host '$host'. Pulando...${NC}"
                        continue
                    fi
                fi

                # Definir o arquivo INI
                cAppserverIniFile="${arquivoappserver_ini}"
                cIniFile="${appserver_dir}/${cAppserverIniFile}"

                # Verificar se o arquivo INI existe
                if [[ "$host" == "localhost" ]]; then
                    if [ ! -f "$cIniFile" ]; then
                        # Procurar por appsrv*.ini
                        log "DEBUG: Procurando arquivos com o padrão ${appserver_dir}/${arquivoappsrv_ini}"
                        files=($(ls ${appserver_dir}/${arquivoappsrv_ini} 2>/dev/null))

                        log "DEBUG: Arquivos encontrados: ${files[@]}"

                        if [ ${#files[@]} -gt 0 ]; then
                            if [ ${#files[@]} -eq 1 ]; then
                                cAppserverIniFile="$(basename "${files[0]}")"
                                cIniFile="${appserver_dir}/${cAppserverIniFile}"
                            else
                                log "${RED}Erro: Mais de um arquivo appsrv*.ini foi encontrado no host '$host' na pasta '$appserver_dir'.${NC}"
                                log "${RED}Arquivos encontrados: ${files[@]}${NC}"
                                continue
                            fi
                        else
                            log "${RED}Nenhum arquivo appsrv*.ini foi encontrado no host '$host' na pasta '$appserver_dir'.${NC}"
                            continue
                        fi
                    fi
                else
                    # Verificar remotamente
                    if ! ssh "$host" "test -f '$cIniFile'"; then
                        # Procurar por appsrv*.ini
                        log "DEBUG: Procurando arquivos com o padrão ${appserver_dir}/${arquivoappsrv_ini} no host '$host'"
                        files=($(ssh "$host" "ls ${appserver_dir}/${arquivoappsrv_ini} 2>/dev/null"))

                        log "DEBUG: Arquivos encontrados no host '$host': ${files[@]}"

                        if [ ${#files[@]} -gt 0 ]; then
                            if [ ${#files[@]} -eq 1 ]; then
                                cAppserverIniFile="$(basename "${files[0]}")"
                                cIniFile="${appserver_dir}/${cAppserverIniFile}"
                            else
                                log "${RED}Erro: Mais de um arquivo appsrv*.ini foi encontrado no host '$host' na pasta '$appserver_dir'.${NC}"
                                log "${RED}Arquivos encontrados: ${files[@]}${NC}"
                                continue
                            fi
                        else
                            log "${RED}Nenhum arquivo appsrv*.ini foi encontrado no host '$host' na pasta '$appserver_dir'.${NC}"
                            continue
                        fi
                    fi
                fi

                # Efetuar backup do arquivo INI
                cIniFileBak="${appserver_dir}/${cFolderBak}/${cAppserverIniFile}.${cDataAtual}.bak"

                if [[ "$host" == "localhost" ]]; then
                    if [ ! -d "${appserver_dir}/${cFolderBak}" ]; then
                        mkdir -p "${appserver_dir}/${cFolderBak}"
                    fi
                    cp "$cIniFile" "$cIniFileBak"
                    if [[ ! -f "$cIniFileBak" ]]; then
                        log "${RED}Falha ao criar arquivo de backup: $cIniFileBak${NC}"
                        continue
                    fi
                else
                    ssh "$host" "mkdir -p '${appserver_dir}/${cFolderBak}'"
                    ssh "$host" "cp '$cIniFile' '$cIniFileBak'"
                    if ! ssh "$host" "test -f '$cIniFileBak'"; then
                        log "${RED}Falha ao criar arquivo de backup: $cIniFileBak no host '$host'${NC}"
                        continue
                    fi
                fi

                # Atualizar o arquivo INI para o novo RPO
                alterar_ini "$cIniFile" "$cEnvironment" "$cKeyINIRPO" "$cRPONewFileAPO" "$host"

            done

            log "${BLUE}------------------------------------------${NC}"

        done
    done

    log "$(date +"%Y-%m-%d %H:%M:%S") | User:$(whoami) | Troca de RPO - $cTipoTrocaDoRpo "

    echo -e "\e[1;32mSucesso!!! \e[0m"
    return 0
}

# Verificar se o parâmetro foi fornecido
if [[ -z "$1" ]]; then
    echo -e "${RED}Informe qual RPO deseja trocar: 'default' ou 'custom'${NC}"
    exit 1
fi

# Verificar se o parâmetro é válido
if [[ "$1" != "default" && "$1" != "custom" ]]; then
    echo -e "${RED}Parâmetro inválido. Informe 'default' ou 'custom'.${NC}"
    exit 1
fi

cTipoTrocaDoRpo="$1"
if [ "$1" = 'custom' ]; then
    echo "Alterando RPO customizado"
    cKeyINIRPO="rpocustom"
fi
if [ "$1" = 'default' ]; then
    echo "Alterando RPO padrão"
    cKeyINIRPO="sourcepath"
fi

change_rpo_file
