# Rig Scanner 3D - Spécifications & Dimensions

## Concept

Boîtier compact tenu à la main (poignée), modulaire, imprimable sur Bambu Lab A1 (256x256x256mm PLA).
Tous les composants sont montés sur un châssis central avec poignée ergonomique intégrée.

```
Vue de face :                    Vue de côté :

      ╱────╲                           ╱────╲
     ╱ L2   ╲  ← inclinable            ╱ L2  ╲  30° recommandé
    ╱────────╲    (0°-45°)            ╱────────╲
         │                                │
      tige Ø15                         tige Ø15
         │                                │
    ┌────┴────┐                      ┌────┴────┐
    │ GoPro   │ ← lentilles          │ GoPro   │
    │ Max     │   dégagées côtés     │ Max     │
    └────┬────┘                      └────┬────┘
    ╔════╧════╗                      ╔════╧════╗
    ║ CHÂSSIS ║ ←rails lat.         ║ RPi5    ║
    ║ ┌─────┐ ║                      ║ 📱 bras ║
    ║ │ RPi5│ ║                      ╚════╤════╝
    ║ └─────┘ ║                           │
    ║    📱   ║                      ┌────┴────┐
    ╚════╤════╝                      │ POIGNÉE │ ← canal câbles
    ┌────┴────┐                      │ (creuse)│
    │ POIGNÉE │                      └────┬────┘
    │ (creuse)│                           │
    └────┬────┘                      gaine USB-C
         │                           vers poche
    ═══╧═══
    gaine 2x USB-C
    vers batteries
    en poche

GoPro SOUS le L2 :
- Lentilles (faces avant/arrière) dégagées vers les côtés → capture optimale
- Tige fine + puck L2 au-dessus = petite obstruction zone haute (peu critique)
- Bâtiments (cible de colorisation) = côtés et bas → bien captés
- L2 au sommet = FOV 360° libre, inclinable pour optimiser la couverture

Batteries en poche :
- ~480g en moins sur le rig (600g au lieu de 1.2kg)
- 2 câbles USB-C dans une gaine passent dans la poignée creuse
- Confort de scan sur longue durée
```

## Dimensions des composants

### Unitree L2 LiDAR
| Param | Valeur | Notes |
|-------|--------|-------|
| Forme | Puck cylindrique | |
| Diamètre | ~102 mm | **À VÉRIFIER sur datasheet officiel** |
| Hauteur | ~55 mm | **À VÉRIFIER** |
| Poids | ~195 g | |
| Fixation | 3-4x M3 sur la base | Pattern circulaire, voir dessin mécanique Unitree |
| Câble | Ethernet RJ45 + DC 12V | Prévoir passage de câbles |

> **ACTION** : télécharger le dessin mécanique officiel depuis unitree.com ou le GitHub unitreerobotics

### Raspberry Pi 5
| Param | Valeur | Source |
|-------|--------|--------|
| Dimensions PCB | 85 x 56 mm | Officiel |
| Trous de fixation | 4x M2.5 | Rectangle 58 x 49 mm |
| Positions des trous | (3.5, 3.5), (61.5, 3.5), (3.5, 52.5), (61.5, 52.5) mm | Depuis coin bas-gauche |
| Hauteur max composants | ~17 mm | Stack USB/Ethernet |
| Poids | ~46 g | Board seule |
| Alimentation | USB-C PD 5V/5A | |

> Source : https://datasheets.raspberrypi.com/rpi5/raspberry-pi-5-mechanical-drawing.pdf

### GoPro Max
| Param | Valeur | Source |
|-------|--------|--------|
| Dimensions | 64 x 69 x 24.6 mm | Officiel GoPro |
| Poids | 154 g | |
| Fixation | GoPro 2-prong (folding fingers) | Pas de 1/4"-20 natif |
| Vis GoPro | M5 x 0.8 | Standard GoPro |
| Slot prong | ~3 mm largeur, ~8 mm espacement | |

Le rig intègre directement un récepteur GoPro 2-prong (pas besoin d'adaptateur).

### Support téléphone
| Param | Valeur | Notes |
|-------|--------|-------|
| Largeur grip | 55-90 mm | Couvre la plupart des téléphones + coque |
| Fixation | Intégrée au châssis | Clamp à vis (plus fiable que ressort en PLA) |
| Angle | Réglable ~45° | Pour voir l'écran en marchant |

### Batteries — DANS LA POCHE
Les batteries ne sont **pas sur le rig**. Elles restent en poche, reliées par 2 câbles USB-C dans une gaine qui passe dans la poignée creuse.

| Batterie | Type | Sortie | Notes |
|----------|------|--------|-------|
| RPi5 | Power bank USB-C PD | 5V/5A | En poche |
| L2 | Power bank USB-C PD + trigger 12V | 12V | En poche, câble USB-C → adaptateur PD trigger 12V |

**Alternative L2** : batterie 12V dédiée (TalentCell) avec câble DC barrel.

### Gaine de câbles
- 2 câbles USB-C dans une gaine tressée Ø12mm
- Passe dans le canal central de la poignée
- Sort en bas vers la poche
- Longueur recommandée : ~80-100cm

## Poids total estimé (rig seul, sans batteries)

| Composant | Poids |
|-----------|-------|
| Unitree L2 | 195 g |
| GoPro Max | 154 g |
| Raspberry Pi 5 | 46 g |
| Châssis PLA | ~100-150 g |
| Tige + poignée PLA | ~80-100 g |
| Visserie/câbles | ~30 g |
| **TOTAL RIG** | **~600 - 680 g** |

Quasiment **moitié moins** qu'avec les batteries embarquées (~1.2 kg avant).

## Contraintes de design

### Impression 3D
- **Imprimante** : Bambu Lab A1
- **Volume max** : 256 x 256 x 256 mm
- **Matériau** : PLA
- **Épaisseur parois** : 2-3 mm minimum (rigidité PLA)
- Si le châssis dépasse 256mm, le découper en 2 pièces avec assemblage par vis/clips

### Modularité
- Fixation GoPro Max : slot GoPro 2-prong avec vis M5 (amovible)
- Fixation Unitree L2 : plateau avec trous M3 (amovible)
- Support téléphone : rail ou bras articulé (amovible)
- Emplacements batteries : berceaux avec sangles velcro ou clips (batteries interchangeables)
- **Évolution future** : points de fixation latéraux pour 2e poignée ou monopode

### Inclinaison du L2
Le L2 a un FOV de 360° × 96° (±48° autour de son plan horizontal).
Le plateau est monté sur une **charnière à crans** pour ajuster l'angle :

```
0° (vertical)          30° (recommandé)        45° (intérieur)

   ┌──┐                    ╱──╲                    ╱──╲
   │L2│                   ╱ L2 ╲                  ╱ L2 ╲
   └──┘                  ╱──────╲                ╱──────╲

Couverture:           Couverture:              Couverture:
  haut: +48°           haut: +78°               haut: +93° (≈plafond)
  bas:  -48°           bas:  -18°               bas:  -3° (≈sol rasant)
  → murs seuls         → sol + murs + haut      → sol + murs + plafond

Usage: façades        Usage: polyvalent        Usage: intérieur pièces
```

**30° incliné vers le bas** est le meilleur compromis :
- Voit le sol (important pour le SLAM, donne des contraintes géométriques)
- Voit les murs (la cible principale)
- Voit le haut des murs / début plafond
- Le SLAM est plus stable (plus de géométrie variée = moins de dérive)

### Ergonomie
- Poignée diamètre ~35-40 mm, longueur ~120 mm
- Centre de gravité le plus bas possible (batteries dans la poignée ou juste au-dessus)
- Accès facile aux ports RPi5 (SSH/écran) et aux boutons GoPro
- Passage de câbles intégré (Ethernet L2→RPi5, USB-C batterie→RPi5, DC batterie→L2)

### Thermique
- Aérations pour le RPi5 (peut chauffer sous charge)
- Le L2 a aussi besoin de ventilation
- Éviter d'enfermer complètement les composants

## Fixations nécessaires (quincaillerie)

| Pièce | Quantité | Usage |
|-------|----------|-------|
| Vis M3 x 8mm | 4 | Fixation Unitree L2 |
| Inserts filetés M3 (heat-set) | 4 | Dans le PLA pour le L2 |
| Vis M2.5 x 6mm | 4 | Fixation RPi5 |
| Inserts filetés M2.5 (heat-set) | 4 | Dans le PLA pour le RPi5 |
| Vis M5 x 25mm (GoPro bolt) | 1 | Fixation GoPro |
| Écrou papillon M5 ou molette | 1 | Serrage GoPro sans outil |
| Vis M4 x 20mm | 4-6 | Assemblage châssis (si multi-pièces) |
| Inserts filetés M4 (heat-set) | 4-6 | Assemblage châssis |
| Sangle velcro 20mm | 2x 200mm | Maintien batteries |
