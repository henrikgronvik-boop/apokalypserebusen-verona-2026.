# Apokalypserebusen 2026 — ende-til-ende testplan (3. november 2026)

Dette er en **testplan**, ikke dokumentasjon på at testene er bestått. Bruk gratis GitHub Actions og Supabase. Test aldri med service-role-nøkkel i klienten. Ikke endre eksisterende konkurransedata under test; bruk isolerte testkontoer eller transaksjoner med ROLLBACK.

## Ufravikelige konkurranseregler
- 34 oppgaver: 25 hovedoppgaver + 3 gamle bonus + 6 spesial. Ingen sletting/erstatning.
- Kun hovedoppgaver teller i 2-av-5-opplåsingen; bonus og spesial teller ikke.
- Spesial: perfect_reconstruction 600 (+200 HK-bonus til beste), recruit_italian 500, italian_charm 400, secret_mission 750, music_video 800, grand_finale 1500.
- secret_mission og grand_finale har HK-styrt samtidig frigivelse. Hemmelig oppdrag: 30 minutter kontrollert av HK. Finale: etter del 5, minst tre gåter og kodeord.
- Frivillig samtykke ved filming av fremmede. Ikke publiser private mediefiler offentlig.

## Testmatrise (må kjøres med lag A, lag B og HK som separate identiteter)
1. Opprett/bruk separate testkontoer for A, B og HK. Kontroller at ingen er administrator ved feil.
2. A ser kun A sine private innsendinger og chat; B ser kun B sine. HK ser nødvendige data for godkjenning.
3. A forsøker direkte SELECT/INSERT/UPDATE/DELETE på B sine innsendinger, chatmeldinger og mediereferanser. Alle uautoriserte operasjoner skal avvises av RLS.
4. A laster opp et bilde og en video. Verifiser privat storage, riktig eier/lag og signert URL; B får ikke tilgang, heller ikke via gjenbruk av A sin filsti.
5. Simuler HTTP 408 og tidsavbrudd ved registrering. Maks tre forsøk, ingen doble medieregistreringer, ingen retry ved 401/403/RLS-avslag.
6. HK får se registrert, men midlertidig utilgjengelig bevis som «ikke tilgjengelig», ikke «ikke levert». HK kan ikke godkjenne uten å åpne nødvendig bevis.
7. HK godkjenner én innsending. Poeng gis én gang; gjentatt godkjenning gir ikke dobbel poengføring.
8. HK avviser innsending. Ingen poeng. Lag kan sende på nytt i tråd med reglene.
9. Fullfør to av fem hovedoppgaver. Neste del låses opp én gang. Fullfør to bonus/spesial uten hovedoppgaver: ingen opplåsing.
10. Forsøk å hoppe over bonus/spesial via UI og direkte databasekall: avvis. Hovedoppgaver følger gjeldende HK-prosess.
11. HK frigir hemmelig oppdrag samtidig til alle lag, registrerer start og håndhever 30-minutters frist. Lag kan ikke frigi oppdrag selv.
12. HK frigir finale først etter del 5; kontroller at alle lag får samme gåter/kodeord og at premie og godkjenning styres av HK.
13. Test mobilnett som faller ut og gjenopptas, store filer innenfor gratisgrensene, og at feil ikke eksponerer private stier eller hemmeligheter.
14. Test at A og B ikke kan endre hverandres poeng, frister, godkjenninger eller lagtilhørighet.

## Rapportering
For hvert testpunkt: dato, testidentiteter (ikke hemmeligheter), forventet resultat, faktisk resultat, PASS/FAIL/BLOKKERT og sporbar commit/CI-kjøring. Kall ikke appen produksjonsklar før hele flyten er bestått på faktiske enheter.

## Observert databasekonfigurasjon 3. november 2026
De seks spesialoppdragene finnes med bonus=true. requires_release=true kun for secret_mission og grand_finale; de fire øvrige er false. Dette er et funn, ikke i seg selv en feil: bekreft ønsket synlighet før eventuell endring.
