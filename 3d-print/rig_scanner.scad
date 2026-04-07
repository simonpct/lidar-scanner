// ============================================================
// RIG SCANNER 3D - Unitree L2 + GoPro Max + RPi5
// ============================================================
// Boîtier compact avec poignée, modulaire, imprimable PLA
// Bambu Lab A1 (256x256x256mm)
//
// Unités : mm
// Conventions : Z = haut, X = droite, Y = profondeur
// ============================================================

// ---- PARAMÈTRES GLOBAUX ----
$fn = 60; // résolution des cylindres

// Tolérances d'impression
tol = 0.3;           // tolérance générale
tol_tight = 0.15;    // ajustement serré (inserts)

// Épaisseur parois PLA
wall = 3;
wall_thin = 2;

// ---- DIMENSIONS COMPOSANTS ----

// Unitree L2 (puck cylindrique) - À VÉRIFIER SUR DATASHEET
// FOV: 360° horizontal × ~96° vertical (±48° autour de l'horizontale du puck)
l2_diameter = 102;
l2_height = 55;
l2_mount_holes = 4;           // nombre de trous
l2_mount_circle_d = 80;       // diamètre du cercle de fixation (À VÉRIFIER)
l2_mount_screw = 3;           // M3

// Angle d'inclinaison du L2
// 0°  = vertical (puck debout) → bon extérieur, voit les murs
// 30° = incliné → compromis, voit sol + murs + début plafond
// 45° = très incliné → max couverture intérieur
l2_tilt_angle = 30;           // degrés, ajustable sur le mount

// Raspberry Pi 5
rpi_w = 85;
rpi_d = 56;
rpi_hole_spacing_x = 58;
rpi_hole_spacing_y = 49;
rpi_hole_offset_x = 3.5;
rpi_hole_offset_y = 3.5;
rpi_screw = 2.5;              // M2.5
rpi_standoff_h = 5;           // hauteur standoff
rpi_component_h = 17;         // hauteur max composants

// GoPro Max
gopro_w = 64;
gopro_d = 24.6;
gopro_h = 69;
gopro_bolt = 5;               // M5
gopro_prong_gap = 3;          // largeur slot
gopro_prong_spacing = 8;      // espacement centre-centre
gopro_prong_depth = 15;       // profondeur des prongs

// Support téléphone
phone_min_w = 55;
phone_max_w = 90;
phone_clamp_d = 15;           // épaisseur du clamp

// Batteries : DANS LA POCHE, pas sur le rig
// 2 câbles USB-C dans une gaine sortent du châssis vers le bas (le long de la poignée)
// - USB-C PD → RPi5
// - USB-C → adaptateur 12V pour L2 (ou câble USB-C PD trigger 12V)
cable_gaine_d = 12;           // diamètre gaine pour 2x USB-C

// Poignée
grip_diameter = 38;
grip_length = 120;
grip_fillet = 5;

// ---- DIMENSIONS CHÂSSIS ----
// Plus compact : juste le RPi5, pas de batteries
chassis_w = rpi_w + 2*wall + 10;        // RPi5 + marge
chassis_d = rpi_d + 2*wall + 10;        // RPi5 + marge
chassis_h = rpi_standoff_h + rpi_component_h + 2*wall;

// Offset vertical GoPro/LiDAR = 100mm
// GoPro EN DESSOUS du L2 : les lentilles (faces avant/arrière) restent
// dégagées vers les côtés. La tige (Ø15mm) + le puck L2 ne masquent
// qu'une petite zone vers le haut = peu critique (bâtiments sont sur les côtés).
// Le L2 au sommet a un scan 360 totalement libre.
gopro_offset_z = 100;

// ============================================================
// MODULES
// ============================================================

// ---- POIGNÉE ERGONOMIQUE (avec canal câbles intégré) ----
module grip() {
    translate([0, 0, -grip_length]) {
        difference() {
            union() {
                // Forme ergonomique : cylindre avec léger renflement
                hull() {
                    cylinder(d=grip_diameter, h=1);
                    translate([0, 0, grip_length/2])
                        cylinder(d=grip_diameter + 4, h=1);
                    translate([0, 0, grip_length])
                        cylinder(d=grip_diameter, h=1);
                }

                // Texture grip (rainures)
                for (i = [0:15:360]) {
                    rotate([0, 0, i])
                    translate([grip_diameter/2 + 0.5, 0, 10])
                        cube([1.5, 1.5, grip_length - 20]);
                }
            }

            // Canal central pour la gaine de câbles (2x USB-C)
            translate([0, 0, -1])
                cylinder(d=cable_gaine_d + 2*tol, h=grip_length + 2);
        }
    }
}

// ---- PLATEAU UNITREE L2 (inclinable) ----
// Le plateau est monté sur une charnière avec des crans d'angle
// pour régler l'inclinaison du scanner selon le contexte :
//   0°  = vertical → scan de façades extérieures
//   30° = incliné  → compromis intérieur/extérieur (recommandé)
//   45° = penché   → scan intérieur (sol + murs + plafond)

function l2_screw_insert_d() = l2_mount_screw + 1.0 + 2*tol_tight; // diamètre insert M3

// Plateau qui reçoit le L2 (la partie inclinée)
module l2_plate() {
    difference() {
        // Plateau circulaire
        cylinder(d=l2_diameter + 2*wall, h=wall);

        // Trous de fixation M3 (inserts heat-set)
        for (i = [0:360/l2_mount_holes:359]) {
            rotate([0, 0, i])
            translate([l2_mount_circle_d/2, 0, -1])
                cylinder(d=l2_screw_insert_d(), h=wall+2);
        }

        // Passage de câbles central
        cylinder(d=25, h=wall+2, center=true);
    }
}

// Charnière avec crans d'angle (0°, 15°, 30°, 45°)
module l2_tilt_hinge() {
    hinge_w = 30;
    hinge_h = 25;
    pivot_d = 8;
    bolt_d = 5;  // M5 comme axe de pivot

    // Base (fixée sur la tige)
    difference() {
        union() {
            // Oreilles de charnière
            for (side = [-1, 1]) {
                translate([side * (hinge_w/2 + 3), 0, 0])
                cube([6, 15, hinge_h], center=true);
            }
        }
        // Trou pivot
        translate([0, 0, 0])
        rotate([0, 90, 0])
            cylinder(d=bolt_d + 2*tol, h=hinge_w + 20, center=true);
    }

    // Crans d'angle (gravés dans les oreilles)
    // Permettent de bloquer à 0°, 15°, 30°, 45°
    for (angle = [0, 15, 30, 45]) {
        rotate([0, 90, 0])
        rotate([0, 0, angle])
        translate([hinge_h/2 - 3, 0, hinge_w/2 + 4])
            cylinder(d=2, h=2);
    }
}

// Assemblage complet du mount L2 inclinable
module l2_mount_plate() {
    // Base de la charnière
    l2_tilt_hinge();

    // Plateau incliné selon l'angle choisi
    rotate([l2_tilt_angle, 0, 0])
    translate([0, 0, 15])
        l2_plate();
}

// ---- RÉCEPTEUR GOPRO (2-PRONG) ----
module gopro_mount() {
    mount_w = 20;
    mount_d = gopro_prong_depth + wall;
    mount_h = 16;

    difference() {
        // Bloc du mount
        translate([-mount_w/2, -mount_d/2, 0])
            cube([mount_w, mount_d, mount_h]);

        // Slot pour les 2 prongs GoPro
        // Prong gauche
        translate([-(gopro_prong_spacing/2 + gopro_prong_gap/2), -gopro_prong_depth/2, wall])
            cube([gopro_prong_gap + 2*tol, gopro_prong_depth + tol, mount_h]);

        // Slot central (entre les prongs)
        translate([-(gopro_prong_gap/2 + tol), -gopro_prong_depth/2, wall])
            cube([gopro_prong_gap + 2*tol, gopro_prong_depth + tol, mount_h]);

        // Prong droite
        translate([(gopro_prong_spacing/2 - gopro_prong_gap/2), -gopro_prong_depth/2, wall])
            cube([gopro_prong_gap + 2*tol, gopro_prong_depth + tol, mount_h]);

        // Trou pour vis M5 (traverse les prongs)
        translate([0, 0, mount_h/2 + wall/2])
        rotate([0, 90, 0])
            cylinder(d=gopro_bolt + 2*tol, h=mount_w + 2, center=true);
    }
}

// ---- SUPPORT RPi5 ----
module rpi5_mount() {
    // Plateau avec standoffs et trous M2.5
    difference() {
        // Plateau de base
        cube([rpi_w + 2*wall, rpi_d + 2*wall, wall]);

        // Aérations (grille)
        for (x = [wall+5 : 8 : rpi_w - 5]) {
            for (y = [wall+5 : 8 : rpi_d - 5]) {
                translate([x, y, -1])
                    cylinder(d=4, h=wall+2);
            }
        }
    }

    // Standoffs M2.5
    rpi5_standoff_positions() {
        difference() {
            cylinder(d=6, h=rpi_standoff_h);
            cylinder(d=rpi_screw + 2*tol_tight, h=rpi_standoff_h + 1);
        }
    }
}

module rpi5_standoff_positions() {
    positions = [
        [rpi_hole_offset_x + wall, rpi_hole_offset_y + wall],
        [rpi_hole_offset_x + rpi_hole_spacing_x + wall, rpi_hole_offset_y + wall],
        [rpi_hole_offset_x + wall, rpi_hole_offset_y + rpi_hole_spacing_y + wall],
        [rpi_hole_offset_x + rpi_hole_spacing_x + wall, rpi_hole_offset_y + rpi_hole_spacing_y + wall]
    ];

    for (pos = positions) {
        translate([pos[0], pos[1], wall])
            children();
    }
}

// ---- PASSAGE DE CÂBLES (gaine vers batteries en poche) ----
module cable_channel() {
    // Canal intégré dans la poignée pour 2x USB-C dans une gaine
    // Sort en bas de la poignée vers la poche
    translate([0, 0, 0])
    difference() {
        cylinder(d=cable_gaine_d + 2*wall, h=grip_length);
        translate([0, 0, -1])
            cylinder(d=cable_gaine_d + 2*tol, h=grip_length + 2);
    }
}

// ---- SUPPORT TÉLÉPHONE (clamp à vis) ----
module phone_clamp_base() {
    // Base du clamp, le mécanisme à vis sera ajouté manuellement
    // ou via un clamp standard du commerce fixé avec insert 1/4"-20

    base_w = 40;
    base_d = 30;
    base_h = 15;
    arm_length = 60;
    arm_angle = 45;

    // Base de fixation au châssis
    difference() {
        cube([base_w, base_d, base_h]);

        // Trous de fixation au châssis (2x M4)
        for (x = [10, base_w - 10]) {
            translate([x, base_d/2, -1])
                cylinder(d=4 + 2*tol, h=base_h + 2);
        }
    }

    // Bras incliné
    translate([base_w/2, base_d/2, base_h])
    rotate([arm_angle, 0, 0])
    translate([0, 0, 0]) {
        difference() {
            cylinder(d=15, h=arm_length);
            // Insert 1/4"-20 au bout (pour clamp standard)
            translate([0, 0, arm_length - 10])
                cylinder(d=6.35 + 2*tol, h=11); // 1/4" = 6.35mm
        }
    }
}

// ---- POINTS DE FIXATION MODULAIRES ----
module rail_slot(length) {
    // Rail en T pour fixations modulaires (futures extensions)
    slot_w = 10;
    slot_depth = 5;
    lip_w = 6;

    translate([-slot_w/2, 0, 0])
    difference() {
        cube([slot_w, length, slot_depth]);
        translate([(slot_w - lip_w)/2, -1, wall_thin])
            cube([lip_w, length + 2, slot_depth]);
    }
}

// ============================================================
// ASSEMBLAGE PRINCIPAL
// ============================================================

module chassis_main() {
    echo(str("Chassis dimensions: ", chassis_w, " x ", chassis_d, " x ", chassis_h, " mm"));
    echo(str("Fits in Bambu A1: ",
        chassis_w <= 256 && chassis_d <= 256 && chassis_h <= 256
        ? "YES" : "NO - NEEDS SPLITTING"));

    color("DodgerBlue", 0.6)
    difference() {
        // Coque extérieure
        hull() {
            cube([chassis_w, chassis_d, chassis_h]);
            // Arrondi des coins
        }

        // Évidement intérieur
        translate([wall, wall, wall])
            cube([chassis_w - 2*wall, chassis_d - 2*wall, chassis_h + 1]);

        // Passage câbles vers la poignée (bas du châssis)
        translate([chassis_w/2, chassis_d/2, -1])
            cylinder(d=cable_gaine_d + 2*tol, h=wall + 2);

        // Ouvertures aération
        for (z = [wall + 10 : 15 : chassis_h - 10]) {
            for (x = [wall + 10 : 12 : chassis_w - 10]) {
                translate([x, -1, z])
                rotate([-90, 0, 0])
                    cylinder(d=5, h=wall + 2);
            }
        }
    }
}

// ---- ASSEMBLAGE COMPLET (preview) ----
// Ordre de bas en haut :
//   Poignée → Châssis (RPi5 + batteries + téléphone) → GoPro → tige → L2 (sommet)
//
// La GoPro est SOUS le L2 :
//   - Ses lentilles (faces avant/arrière) sont dégagées vers les côtés
//   - La tige fine (Ø15mm) + puck L2 en haut = petite obstruction haute (peu critique)
//   - Le L2 au sommet a un FOV 360° totalement libre
//   - Les bâtiments (= ce qu'on colorise) sont sur les côtés et en bas → bien captés

module full_assembly() {
    // ---- POIGNÉE (en bas) ----
    color("DimGray")
    translate([chassis_w/2, chassis_d/2, 0])
        grip();

    // ---- CHÂSSIS ----
    translate([0, 0, 0])
        chassis_main();

    // RPi5
    color("Green", 0.7)
    translate([wall + 5, wall + 5, wall])
        rpi5_mount();

    // Canal de câbles (dans la poignée, vers les batteries en poche)
    color("Orange", 0.4)
    translate([chassis_w/2, chassis_d/2, -grip_length])
        cable_channel();

    // ---- GOPRO MAX (juste au-dessus du châssis) ----
    // Mount GoPro sur le châssis
    gopro_z = chassis_h;  // base du mount GoPro

    color("Red", 0.7)
    translate([chassis_w/2, chassis_d/2, gopro_z])
        gopro_mount();

    // GoPro (fantôme pour preview)
    %color("Black", 0.3)
    translate([chassis_w/2 - gopro_w/2, chassis_d/2 - gopro_d/2,
               gopro_z + 16])  // 16 = hauteur du mount
        cube([gopro_w, gopro_d, gopro_h]);

    // ---- TIGE DE LIAISON GoPro → L2 ----
    tige_base_z = gopro_z + 16 + gopro_h;  // au-dessus de la GoPro
    tige_length = gopro_offset_z - gopro_h - 16;  // ce qui reste pour atteindre 100mm d'offset

    color("Silver", 0.7)
    translate([chassis_w/2, chassis_d/2, tige_base_z])
        cylinder(d=15, h=tige_length);

    // ---- PLATEAU UNITREE L2 INCLINABLE (sommet) ----
    l2_base_z = tige_base_z + tige_length;

    color("Orange", 0.7)
    translate([chassis_w/2, chassis_d/2, l2_base_z])
        l2_mount_plate();

    // LiDAR (fantôme pour preview, incliné)
    %color("DarkGray", 0.3)
    translate([chassis_w/2, chassis_d/2, l2_base_z])
    rotate([l2_tilt_angle, 0, 0])
    translate([0, 0, 15 + wall])
        cylinder(d=l2_diameter, h=l2_height);

    // ---- SUPPORT TÉLÉPHONE (côté droit) ----
    color("Teal", 0.7)
    translate([chassis_w - 45, 0, chassis_h - 20])
        phone_clamp_base();

    // ---- RAILS MODULAIRES (côtés) ----
    color("Yellow", 0.5) {
        // Rail gauche
        translate([0, chassis_d/2, chassis_h/2])
        rotate([0, -90, 0])
            rail_slot(chassis_d - 20);

        // Rail droit
        translate([chassis_w, chassis_d/2, chassis_h/2])
        rotate([0, 90, 0])
            rail_slot(chassis_d - 20);
    }
}

// ============================================================
// PIÈCES INDIVIDUELLES POUR IMPRESSION
// ============================================================

// Décommenter UNE pièce à la fois pour l'export STL

// 1. Châssis principal (compact, juste RPi5)
// chassis_main();

// 2. Plateau L2 inclinable (charnière + plateau)
// l2_mount_plate();

// 3. Mount GoPro (2-prong)
// gopro_mount();

// 4. Support RPi5
// rpi5_mount();

// 5. Base clamp téléphone
// phone_clamp_base();

// 6. Poignée (avec canal câbles intégré)
// grip();

// ---- VUE ASSEMBLAGE COMPLET ----
full_assembly();
