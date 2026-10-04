# kontor-runner-valvur

Valvur [kontor-runner](https://github.com/Laudur/kontor-runner) agendile. Agent
lubab kontori arvutit GitHub Actionsi runnerina ja suunab töid repo muutujaga
`KONTOR_RUNNER` (`on` → kontori arvuti, muu → GitHubi masinad). Kui arvuti või
agent kukub ootamatult ära (voolukatkestus, kokkujooksmine), jääb muutuja `on`
peale ja tööd ootavad runnerit, mida pole.

[`valvur.sh`](valvur.sh) jookseb iga 10 min ([töövoog](.github/workflows/valvur.yml)) ja
paneb muutuja kõigis repodes `off` ning saadab ootel tööd GitHubi, kui

- ükski kontori runner pole online ja muutuja on olnud `on` vähemalt 5 min, või
- mõnes repos ootab töö kontori runnerit üle 10 min ja selle repo runnereid pole online.

Agent paneb muutuja ise uuesti `on`, kui runnerid on tagasi. Korrektsel sulgemisel
paneb agent muutuja ise `off` — valvur on varuvõrk.

Repo on avalik, sest avalikes repodes on GitHubi masinad tasuta: valvur ei kuluta
privaatrepode Actions-minuteid. Siin pole midagi salajast; GitHubi võti on repo
saladus `KONTOR_VALVUR_TOKEN` — peeneteraline PAT ainult neljale repole: Actions
(read/write), Variables (read/write), Administration (read).

Käsitsi: Actions → Valvur → Run workflow (soovi korral „dry run“), või kohalikult
`DRY_RUN=1 ./valvur.sh` (vajab `gh`-d).
