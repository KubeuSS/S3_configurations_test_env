```bash
chmod +x *
```
Nadanie uprawnień wszystkim skryptom w folderze.

```bash
./setup
```
Sprawdza i pobierania wymagania.

```bash
./cluster_sim up
```

Tworzy 6 maszyn wirtualnych (VM-1 do VM-6), każda z 1 CPU, 1 GB RAM, 8 GB dysku. Zapisuje adresy IP do `nodes_ips.txt`.


```bash
./run_all
```
Uruchamia proces wdrożenia klastra minio na VM. Przeprowadza zestaw testów o zapisanych konfiguracjach w folderze configs. Zapisuje wyniki do results.

```bash
./minio_clear
```
Usuwa minio z VM.

```bash
./garage_test
```
Usuwa Garage z VM.

```bash
./cluster_sim destroy
```
Usuwa maszyny wirtualne.
