## Zautomatyzowane środowisko do testów wydajnościowych rozproszonych magazynów obiektowych S3 - MinIO i Garage.
### Projekt buduje lokalny klaster 6 maszyn wirtualnych (Multipass/Ubuntu 22.04) i automarycznie wdraża zapisane konfigurajce magazynów następnie przeprowadzając serię testów z wykorzystaniem narzędzia warp. Następnie wyniki zapisywane są do folderu results w formacie json.

<br>

```bash
chmod +x *
```
Nadanie uprawnień wszystkim skryptom w folderze.

<br>

```bash
./setup
```
Sprawdza i pobierania wymagania.

<br>

```bash
./cluster_sim up
```

Tworzy 6 maszyn wirtualnych (VM-1 do VM-6), każda z 1 CPU, 1 GB RAM, 8 GB dysku. Zapisuje adresy IP do `nodes_ips.txt`.


<br>

```bash
./run_all
```
Uruchamia proces wdrożenia klastra minio na VM. Przeprowadza zestaw testów o zapisanych konfiguracjach w folderze configs. Zapisuje wyniki do results.

<br>

```bash
./minio_clear
```
Usuwa minio z VM.

<br>

```bash
./garage_deploy
```
Wdraża klaster Garage na VM.

<br>

```bash
./garage_test
```
Przeprowadza testy Garage i zapisuje wynik do results.

<br>

```bash
./garage_test
```
Usuwa Garage z VM.
