# Manager RPO TOTVS Protheus 

Trata-se da versão em powershell do Manager RPO que faz a cópia, backup e substituição dos arquivos .ini do protheus para reaportar para o novo arquivo com os programas novos compilados. 

Utiliza o conceito de troca a quente do Repositório de Objetos do protheus. 


## Servidores secundários 
Para trocar o RPO em outro servidores, será necessário utilizar o NFS 

https://tdn.totvs.com/display/PROT/Protheus+em+Linux+-+Configurar+o+NFS



### Melhorias
 - Alterar para também utilizar SSH ao invés de NFS 
    https://tdn.totvs.com/pages/viewpage.action?pageId=825303316