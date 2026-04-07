# Rig Scanner 3D - Impression 3D

## Fichiers

| Fichier | Description |
|---------|-------------|
| `specs.md` | Spécifications et dimensions de tous les composants |
| `rig_scanner.scad` | Design paramétrique OpenSCAD complet |

## Pièces à imprimer

Le rig est composé de **8 pièces modulaires** :

| # | Pièce | Infill | Notes |
|---|-------|--------|-------|
| 1 | Châssis principal | 20-25% | Compact (juste RPi5), passage câbles central |
| 2 | Plateau L2 inclinable | 40% | Charnière à crans (0°/15°/30°/45°) |
| 3 | Mount GoPro (2-prong) | 50% | Petit mais doit être solide (vis M5) |
| 4 | Support RPi5 | 20% | Avec aérations intégrées |
| 5 | Base clamp téléphone | 30% | Bras incliné 45° |
| 6 | Poignée | 30% | Canal central creux pour gaine 2x USB-C |

## Paramètres d'impression recommandés (Bambu Lab A1)

- **Matériau** : PLA
- **Hauteur de couche** : 0.2 mm (0.16 pour le mount GoPro)
- **Parois** : 3 périmètres
- **Supports** : selon la pièce (le châssis en aura besoin pour les ouvertures d'aération)
- **Orientation** : imprimer chaque pièce avec la plus grande surface plane vers le bas

## Quincaillerie nécessaire

| Pièce | Qty | Usage |
|-------|-----|-------|
| Insert M3 heat-set | 4 | Plateau L2 |
| Insert M2.5 heat-set | 4 | Support RPi5 |
| Insert M4 heat-set | 4-6 | Assemblage châssis |
| Vis M3 x 8mm | 4 | Fixation L2 |
| Vis M2.5 x 6mm | 4 | Fixation RPi5 |
| Vis M5 x 25mm + écrou papillon | 2 | GoPro + axe charnière L2 |
| Vis M4 x 16mm | 4-6 | Assemblage |
| Gaine tressée Ø12mm x 1m | 1 | Protection 2x câbles USB-C |
| Câble USB-C 1m | 2 | Alimentation RPi5 + L2 |

## Comment utiliser le fichier OpenSCAD

1. Ouvrir `rig_scanner.scad` dans [OpenSCAD](https://openscad.org/)
2. `F5` pour preview rapide, `F6` pour rendu complet
3. Pour exporter une pièce STL :
   - Commenter `full_assembly();` en bas du fichier
   - Décommenter la pièce souhaitée (ex: `chassis_main();`)
   - `F6` puis `File > Export > STL`
4. Importer le STL dans Bambu Studio

## Avant d'imprimer

1. **Vérifier les dimensions du Unitree L2** sur le dessin mécanique officiel
2. **Acheter les batteries exactes** et mesurer au pied à coulisse
3. **Imprimer d'abord le mount GoPro** (petit, rapide) pour tester l'ajustement
4. **Imprimer le plateau L2** pour vérifier l'alignement des trous
5. Ensuite seulement imprimer le châssis et la poignée

## Modularité / Évolutions futures

- **Rails latéraux en T** : pour fixer une 2e poignée, un bras additionnel, etc.
- **Batteries** : les berceaux sont interchangeables, adapter à n'importe quel modèle
- **Monopode** : ajouter un insert 1/4"-20 ou 3/8"-16 sous la poignée
- **2e poignée** : concevoir un grip symétrique qui se fixe sur les rails latéraux
