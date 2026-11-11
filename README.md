# win11-setup-automation

Automação _Zero-Touch_ para instalação do Windows 11 com bypass de hardware e instalação de softwares..

**Requisito:** O computador deve estar conectado a uma rede cabeada durante a formatação..

## Estrutura do Pendrive

O pendrive bootável do Windows deve ser organizado exatamente desta forma na raiz:

```text
Pendrive/
 ├── boot/
 ├── efi/
 ├── sources/
 ├── setup.exe
 ├── Autounattend.xml           Arquivo de resposta na raiz
 └── Windows-Installer/         Pasta deste repositório
      ├── config/
      │   └── programs.json
      └── scripts/
          ├── installers.ps1
          └── main.ps1
```
