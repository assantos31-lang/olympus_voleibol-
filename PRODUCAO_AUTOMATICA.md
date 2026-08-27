# Publicação automática do Olympus

A publicação é acionada por um marcador Git no formato `production-X.Y.Z`.
O mesmo número de versão é usado na App Store e no Google Play.

## Fluxo

1. O código precisa estar registrado na branch `main`, sem alterações locais pendentes.
2. Execute `tool/release_production.ps1 -Version X.Y.Z`.
3. O Codemagic executa análise estática e testes.
4. O número interno de cada build é calculado a partir do maior número já existente na respectiva loja.
5. O Android App Bundle é enviado para 100% da faixa de produção.
6. O IPA é submetido à revisão da Apple e liberado automaticamente após a aprovação.

## Credenciais esperadas no Codemagic

- Integração Apple Developer Portal: `Codemagic Admin`.
- Chave Android: `olympus_upload_key`.
- Grupo de variáveis: `google_play_credentials`.
- Segredo no grupo: `GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS`.

Credenciais, certificados e arquivos de assinatura nunca devem ser incluídos em novos commits.
