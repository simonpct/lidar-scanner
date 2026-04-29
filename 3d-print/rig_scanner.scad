// ===============================================
// SUPPORT RIG SCANNER - LiDAR L2 + GoPro Max + RPi5
// Optimisé pour impression PLA sur Bambu Lab A1
// Tout est centré sur X=0, Y=0. Z=0 = sol.
// X = axe court (Pi width), Y = axe long (Pi length)
// LiDAR faces +Y (right when holding)
//
// PIÈCES (changer 'part' pour exporter) :
//   "all"         — vue assemblée
//   "base"        — RPi holder (assemblé)
//   "base_bottom" — Fond + parois basses
//   "base_top"    — Couvercle + ventilation
//   "arch_r"      — Arche droite (+Y)
//   "arch_l"      — Arche gauche (-Y)
//   "v_top"       — V convergent + barre GoPro
//   "handle"      — Poignée + struts
//   "lidar"       — Crossbar + platine LiDAR
//   "cap_r"       — Capot orange droit
//   "cap_l"       — Capot orange gauche
//
// VISSERIE : M3x16 vis+écrou (arche-base)
//            M3x12 vis+écrou (V-arche, LiDAR crossbar)
//            1/4" vis traversante par le dessous (GoPro)
// ===============================================

// --- SÉLECTEUR DE PIÈCE ---
part = "all";  // Changer ici pour exporter une pièce

$fn = 60;

// --- PARAMÈTRES RASPBERRY PI 5 + HAT SSD + FAN ---
rpi_length = 85;
rpi_width = 56;
rpi_stack_height = 35;
rpi_clearance = 1.5;

// --- PARAMÈTRES STRUCTURE ---
wall = 3;
bar_w = 10;
bar_d = 6;
bar_r = 2;
arch_gap = 15;
arch_height = 120;
zigzag_period = 12;
zigzag_thick = 2.5;

// --- PARAMÈTRES V ET GOPRO ---
v_rise = 5;
v_thickness = 12;
gopro_screw_diam = 6.35;  // 1/4"
gopro_bar_len = 50;
gopro_bar_sec = 15;

// --- PARAMÈTRES LIDAR ---
lidar_diam = 75;
lidar_y_offset = 0;        // Centré entre les arches (axe Y)
lidar_forward_offset = 25; // Avancé vers l'avant (+X) pour réduire la zone grise
lidar_tilt = 45;
lidar_mount_z = 80;
lidar_bolt_radius = 25;    // Distance centre LiDAR → centre vis M3
lidar_plate_thick = 5;     // Épaisseur platine
lidar_plate_size = 65;     // Taille platine (cercle)

// --- PARAMÈTRES POIGNÉE ---
handle_width = 28;      // Largeur (axe Y)
handle_depth = 24;      // Profondeur (axe X)
handle_r = 5;
handle_offset = 35;
handle_grip_len = 80;   // Longueur de la zone de prise
handle_tilt = 12;       // Inclinaison pistolet (degrés vers l'avant)
handle_bulge = 3;       // Renflement central paume
beaver_tail_h = 15;     // Hauteur de l'extension beaver tail
beaver_tail_d = 6;      // Profondeur supplémentaire beaver tail

// --- VISSERIE ---
bolt_diam = 3.4;       // M3 passage libre
bolt_head_diam = 6.2;  // Tête M3 hex
bolt_head_depth = 3;   // Profondeur fraisage tête
nut_w = 6.4;           // Largeur écrou M3 (plat à plat)
nut_depth = 2.5;       // Épaisseur écrou M3

// --- COULEURS ---
c_main = [0.1, 0.1, 0.1];
c_accent = [1.0, 0.4, 0.0];

// --- VALEURS CALCULÉES ---
hol_l = rpi_width + rpi_clearance*2 + wall*2;
hol_w = rpi_length + rpi_clearance*2 + wall*2;
hol_h = rpi_stack_height + wall*2;

arch_footprint = bar_d*2 + arch_gap;
base_l = hol_l;
base_w = hol_w + (arch_footprint + wall)*2;

arch_top_z = hol_h + arch_height;
total_top_z = arch_top_z + v_rise + gopro_bar_sec;

arch_bx1 = -(arch_gap/2 + bar_w/2);
arch_bx2 =  (arch_gap/2 + bar_w/2);

arch_y_inner_pos = hol_w/2 + bar_d/2;
arch_y_outer_pos = hol_w/2 + bar_d*1.5 + arch_gap;

lidar_center_y = lidar_y_offset;

// Paramètres cadre
frame_wall = 2;
frame_chamfer = 1;

// Capot orange
cap_height = 5;
cap_clearance = 0.3;
cap_lip = 1.5;


// ===============================================
// UTILITAIRES
// ===============================================

module rounded_bar(w, d, h, r) {
    translate([0, 0, h/2])
        minkowski() {
            cube([w - 2*r, d - 2*r, h - 0.01], center=true);
            cylinder(h=0.01, r=r, center=true);
        }
}

// Trou de vis M3 vertical traversant + fraisage tête en bas
module m3_hole_head_bottom(depth) {
    translate([0, 0, -1])
        cylinder(h=depth + 2, d=bolt_diam);
    // Fraisage tête en bas
    translate([0, 0, -0.01])
        cylinder(h=bolt_head_depth, d=bolt_head_diam);
}

// Trou de vis M3 vertical traversant + piège écrou en haut
module m3_hole_nut_top(depth, nut_z) {
    translate([0, 0, -1])
        cylinder(h=depth + 2, d=bolt_diam);
    // Piège écrou hexagonal
    translate([0, 0, nut_z])
        cylinder(h=nut_depth + 0.5, d=nut_w, $fn=6);
}

// Trou de vis M3 vertical traversant + piège écrou en bas
module m3_hole_nut_bottom(depth) {
    translate([0, 0, -1])
        cylinder(h=depth + 2, d=bolt_diam);
    translate([0, 0, -0.01])
        cylinder(h=nut_depth + 0.5, d=nut_w, $fn=6);
}

// Trou de vis M3 horizontal + piège écrou
module m3_hole_horiz(length) {
    rotate([90, 0, 0])
        cylinder(h=length, d=bolt_diam, center=true);
}

// ===============================================
// PIÈCE 1A : BASE BOTTOM (fond + parois basses)
// ===============================================

// Hauteur de séparation
split_z = hol_h / 2;
// Joint emboîtement
joint_lip = 1.5;    // Hauteur de la lèvre
joint_cl = 0.2;     // Jeu

module base_bottom() {
    in_l = rpi_width + rpi_clearance*2;
    in_w = rpi_length + rpi_clearance*2;

    color(c_main) difference() {
        union() {
            // Coque extérieure coupée à split_z
            intersection() {
                translate([0, 0, hol_h/2])
                    minkowski() {
                        cube([base_l - 6, base_w - 6, hol_h - 2], center=true);
                        sphere(3);
                    }
                // Couper au plan de séparation
                translate([0, 0, -50])
                    cube([base_l + 20, base_w + 20, split_z + 50], center=false);
            }

            // Lèvre mâle (rebord pour emboîtement)
            translate([0, 0, split_z])
                difference() {
                    minkowski() {
                        cube([in_l - 2, in_w - 2, joint_lip*2], center=true);
                        cylinder(h=0.01, r=1, center=true);
                    }
                    translate([0, 0, -1])
                        minkowski() {
                            cube([in_l - 2 - wall, in_w - 2 - wall, joint_lip*2 + 2], center=true);
                            cylinder(h=0.01, r=1, center=true);
                        }
                }
        }

        // Évidement intérieur Pi
        translate([-in_l/2, -in_w/2, wall])
            cube([in_l, in_w, split_z + joint_lip + 1]);

        // Stries verticales — Face +X
        for (y = [-base_w/2 + 6 : 5 : base_w/2 - 6]) {
            translate([base_l/2 - 1, y - 0.75, wall + 2])
                cube([4, 1.5, split_z - wall - 2]);
        }
        // Face -X
        for (y = [-base_w/2 + 6 : 5 : base_w/2 - 6]) {
            translate([-base_l/2 - 3, y - 0.75, wall + 2])
                cube([4, 1.5, split_z - wall - 2]);
        }
        // Face +Y
        for (x = [-base_l/2 + 6 : 5 : base_l/2 - 6]) {
            translate([x - 0.75, base_w/2 - 1, wall + 2])
                cube([1.5, 4, split_z - wall - 2]);
        }
        // Face -Y
        for (x = [-base_l/2 + 6 : 5 : base_l/2 - 6]) {
            translate([x - 0.75, -base_w/2 - 3, wall + 2])
                cube([1.5, 4, split_z - wall - 2]);
        }

        // Ouverture câbles côté -X (poignée)
        translate([-base_l/2 - 2, 0, wall + 2])
            rotate([0, 90, 0])
                minkowski() {
                    cube([6, 10, base_l/2 + 4], center=true);
                    sphere(2);
                }

        // Trous vis sous la base (M3, aux 4 coins)
        for (dx = [-(base_l/2 - 8), (base_l/2 - 8)]) {
            for (dy = [-(base_w/2 - 8), (base_w/2 - 8)]) {
                translate([dx, dy, -5])
                    cylinder(h=wall + 10, d=bolt_diam);
                translate([dx, dy, -5])
                    cylinder(h=5 + bolt_head_depth, d=bolt_head_diam);
            }
        }

        // Trous vis assemblage bottom↔top (M3, 4 trous dans les coins intérieurs)
        for (dx = [-(in_l/2 - 6), (in_l/2 - 6)]) {
            for (dy = [-(in_w/2 - 6), (in_w/2 - 6)]) {
                translate([dx, dy, split_z - 10])
                    cylinder(h=12, d=bolt_diam);
                translate([dx, dy, split_z - nut_depth])
                    cylinder(h=nut_depth + 0.5, d=nut_w, $fn=6);
            }
        }
    }
}

// ===============================================
// PIÈCE 1B : BASE TOP (couvercle)
// ===============================================

module base_top() {
    in_l = rpi_width + rpi_clearance*2;
    in_w = rpi_length + rpi_clearance*2;

    color(c_main) difference() {
        union() {
            // Coque extérieure : de split_z au sommet
            intersection() {
                translate([0, 0, hol_h/2])
                    minkowski() {
                        cube([base_l - 6, base_w - 6, hol_h - 2], center=true);
                        sphere(3);
                    }
                translate([0, 0, split_z])
                    cube([base_l + 20, base_w + 20, hol_h], center=false);
            }

            // Boss pour vis pied LiDAR
            translate([lidar_forward_offset, lidar_center_y, hol_h])
                cylinder(h=wall, d=bolt_head_diam + wall*3);

            // Cadre renforcé passe câble
            translate([in_l/4, -in_w/4, hol_h - wall])
                difference() {
                    minkowski() {
                        cube([12, 14, wall + 2], center=true);
                        sphere(1);
                    }
                    cube([9, 11, wall + 6], center=true);
                }
        }

        // Évidement intérieur (continue depuis split_z)
        translate([-in_l/2, -in_w/2, split_z - 1])
            cube([in_l, in_w, hol_h - split_z + 2]);

        // Rebord femelle (pour emboîtement avec bottom)
        translate([0, 0, split_z])
            minkowski() {
                cube([in_l - 2 + joint_cl, in_w - 2 + joint_cl, joint_lip*2 + 0.1], center=true);
                cylinder(h=0.01, r=1, center=true);
            }

        // Grille ventilation diagonale sur le dessus
        intersection() {
            translate([0, 0, hol_h])
                minkowski() {
                    cube([in_l - 10, in_w - 10, 18], center=true);
                    cylinder(h=1, r=3, center=true);
                }
            for (i = [-12 : 1 : 12]) {
                rotate([0, 0, 45])
                    translate([i * 8, 0, hol_h])
                        minkowski() {
                            cube([1, in_l + in_w, 18], center=true);
                            cylinder(h=1, r=1, center=true);
                        }
            }
        }

        // Stries verticales (partie haute) — Face +X
        for (y = [-base_w/2 + 6 : 5 : base_w/2 - 6]) {
            translate([base_l/2 - 1, y - 0.75, split_z])
                cube([4, 1.5, hol_h - split_z - wall]);
        }
        // Face -X
        for (y = [-base_w/2 + 6 : 5 : base_w/2 - 6]) {
            translate([-base_l/2 - 3, y - 0.75, split_z])
                cube([4, 1.5, hol_h - split_z - wall]);
        }
        // Face +Y
        for (x = [-base_l/2 + 6 : 5 : base_l/2 - 6]) {
            translate([x - 0.75, base_w/2 - 1, split_z])
                cube([1.5, 4, hol_h - split_z - wall]);
        }
        // Face -Y
        for (x = [-base_l/2 + 6 : 5 : base_l/2 - 6]) {
            translate([x - 0.75, -base_w/2 - 3, split_z])
                cube([1.5, 4, hol_h - split_z - wall]);
        }

        // Passe câble dessus
        translate([in_l/4, -in_w/4, hol_h - wall])
            minkowski() {
                cube([8, 10, wall + 4], center=true);
                sphere(1.5);
            }

        // Trous vis arches : vis par le bas, tête en bas, écrou dans l'arche
        for (side = [1, -1]) {
            for (bx = [arch_bx1, arch_bx2]) {
                for (by_off = [arch_y_inner_pos, arch_y_outer_pos]) {
                    translate([bx, side * by_off, 0])
                        m3_hole_head_bottom(hol_h);
                }
            }
        }

        // Trous vis poignée → base (M3 horizontal)
        for (dy = [-handle_width/4, handle_width/4]) {
            translate([-base_l/2 - 5, dy, hol_h/2])
                rotate([0, 90, 0])
                    cylinder(h=20, d=bolt_diam);
            translate([-hol_l/2 + nut_depth, dy, hol_h/2])
                rotate([0, 90, 0])
                    cylinder(h=nut_depth + 0.5, d=nut_w, $fn=6);
        }

        // Trou vis pied LiDAR
        translate([lidar_forward_offset, lidar_center_y, -5])
            cylinder(h=hol_h + wall + 15, d=bolt_diam);
        translate([lidar_forward_offset, lidar_center_y, -0.01])
            cylinder(h=nut_depth + 0.5, d=nut_w, $fn=6);

        // Trous vis assemblage bottom↔top (M3, tête en haut)
        for (dx = [-(in_l/2 - 6), (in_l/2 - 6)]) {
            for (dy = [-(in_w/2 - 6), (in_w/2 - 6)]) {
                translate([dx, dy, split_z - 2])
                    cylinder(h=hol_h, d=bolt_diam);
                translate([dx, dy, hol_h - bolt_head_depth])
                    cylinder(h=bolt_head_depth + 5, d=bolt_head_diam);
            }
        }
    }
}

// Vue assemblée des deux parties de la base
module rpi_holder() {
    base_bottom();
    base_top();
}

// ===============================================
// PIÈCE 2 & 3 : ARCHES
// ===============================================

module arch(side=1) {
    y_inner = side * arch_y_inner_pos;
    y_outer = side * arch_y_outer_pos;

    frame_x = arch_gap + bar_w*2;
    frame_y = abs(y_outer - y_inner) + bar_d;
    frame_cy = (y_inner + y_outer) / 2;

    difference() {
        union() {
            // 4 barres arrondies (noir)
            color(c_main)
            for (bx = [arch_bx1, arch_bx2]) {
                for (by = [y_inner, y_outer]) {
                    translate([bx, by, 0])
                        rounded_bar(bar_w, bar_d, arch_top_z, bar_r);
                }
            }

            // Rectangle cadre outline — masqué pour visualisation
            /*
            color(c_main) {
                arch_h = arch_top_z - hol_h;
                for (sx = [-1, 1]) {
                    for (sy = [-1, 1]) {
                        translate([sx*(frame_x/2 + frame_wall/2), frame_cy + sy*(frame_y/2 + frame_wall/2), hol_h + arch_h/2])
                            rotate([0, 0, 45])
                                cube([frame_wall*1.4, frame_wall*1.4, arch_h], center=true);
                    }
                }
                for (sx = [-1, 1]) {
                    translate([sx*(frame_x/2 + frame_wall/2), frame_cy, arch_top_z - frame_wall/2])
                        cube([frame_wall, frame_y + frame_wall*2, frame_wall], center=true);
                }
                for (sy = [-1, 1]) {
                    translate([0, frame_cy + sy*(frame_y/2 + frame_wall/2), arch_top_z - frame_wall/2])
                        cube([frame_x + frame_wall*2, frame_wall, frame_wall], center=true);
                }
                for (sx = [-1, 1]) {
                    translate([sx*(frame_x/2 + frame_wall/2), frame_cy, hol_h + frame_wall/2])
                        cube([frame_wall, frame_y + frame_wall*2, frame_wall], center=true);
                }
                for (sy = [-1, 1]) {
                    translate([0, frame_cy + sy*(frame_y/2 + frame_wall/2), hol_h + frame_wall/2])
                        cube([frame_x + frame_wall*2, frame_wall, frame_wall], center=true);
                }
            }
            */

            // Zigzags (noir)
            color(c_main) {
                zigzag_x(
                    x1 = arch_bx1 + bar_w/2,
                    x2 = arch_bx2 - bar_w/2,
                    y = y_inner,
                    z0 = hol_h, z1 = arch_top_z
                );
                zigzag_x(
                    x1 = arch_bx1 + bar_w/2,
                    x2 = arch_bx2 - bar_w/2,
                    y = y_outer,
                    z0 = hol_h, z1 = arch_top_z
                );
                zigzag_y(
                    y1 = y_inner + side*bar_d/2,
                    y2 = y_outer - side*bar_d/2,
                    x = arch_bx1,
                    z0 = hol_h, z1 = arch_top_z,
                    side = side
                );
                zigzag_y(
                    y1 = y_inner + side*bar_d/2,
                    y2 = y_outer - side*bar_d/2,
                    x = arch_bx2,
                    z0 = hol_h, z1 = arch_top_z,
                    side = side
                );
            }

            // Renforts horizontaux (arrondis comme les barres)
            color(c_main) {
                // Renfort haut
                translate([0, frame_cy, arch_top_z - bar_d])
                    minkowski() {
                        cube([frame_x - bar_r*2, frame_y - bar_r*2, bar_d/2 - 0.01], center=true);
                        cylinder(h=0.01, r=bar_r, center=true);
                    }
                // Renfort au niveau de la crossbar LiDAR (épaissi pour la vis)
                translate([0, frame_cy, lidar_mount_z - bar_w * 1.5])
                    minkowski() {
                        cube([frame_x - bar_r*2, frame_y - bar_r*2, bar_w - 0.01], center=true);
                        cylinder(h=0.01, r=bar_r, center=true);
                    }
            }
        }

        // Trous vis bas (arche→base) : écrou piégé en bas de l'arche
        for (bx = [arch_bx1, arch_bx2]) {
            for (by = [y_inner, y_outer]) {
                translate([bx, by, 0])
                    m3_hole_nut_bottom(hol_h);
            }
        }

        // Trou vis crossbar LiDAR : horizontal, écrou piégé (crossbar abaissée)
        translate([arch_bx2, y_inner, lidar_mount_z - bar_w * 1.5]) {
            rotate([90, 0, 0])
                cylinder(h=bar_d + 2, d=bolt_diam, center=true);
            // Piège écrou côté extérieur
            translate([0, -bar_d/2, 0])
                rotate([90, 0, 0])
                    cylinder(h=nut_depth + 0.5, d=nut_w, $fn=6);
        }

        // Évidement pour capot orange
        translate([0, frame_cy, arch_top_z - cap_lip])
            cube([frame_x + frame_wall*2 + cap_clearance*2, frame_y + frame_wall*2 + cap_clearance*2, cap_lip*2 + 1], center=true);
    }
}

// Capot orange — moitié haute seulement, posé flush sur le dessus des arches
module arch_cap(side) {
    y_inner = side * arch_y_inner_pos;
    y_outer = side * arch_y_outer_pos;
    frame_x = arch_gap + bar_w*2 + frame_wall*2;
    frame_y = abs(y_outer - y_inner) + bar_d + frame_wall*2;
    frame_cy = (y_inner + y_outer) / 2;

    cap_r = 3;

    color(c_accent)
    translate([0, frame_cy, arch_top_z]) {
        // Rounded square bombé, coupé en dessous pour ne garder que le haut
        difference() {
            minkowski() {
                cube([frame_x - cap_r*2, frame_y - cap_r*2, cap_height/2], center=true);
                sphere(cap_r);
            }
            // Couper tout ce qui est en dessous de Z=arch_top_z
            translate([0, 0, -(cap_height/2 + cap_r + 1)])
                cube([frame_x + 10, frame_y + 10, cap_height + cap_r*2], center=true);
        }

        // Lèvres de clip en bas (juste sous le plan de coupe)
        for (sx = [-1, 1]) {
            translate([sx * (frame_x/2 - 2), 0, -cap_lip/2])
                cube([cap_lip, frame_y * 0.4, cap_lip], center=true);
        }
        for (sy = [-1, 1]) {
            translate([0, sy * (frame_y/2 - 2), -cap_lip/2])
                cube([frame_x * 0.4, cap_lip, cap_lip], center=true);
        }
    }
}

// Zigzag sur face X
module zigzag_x(x1, x2, y, z0, z1) {
    gap = x2 - x1;
    n = floor((z1 - z0) / zigzag_period);
    for (i = [0 : n-1]) {
        z = z0 + i * zigzag_period;
        if (i % 2 == 0) {
            hull() {
                translate([x1, y, z]) cube([zigzag_thick, zigzag_thick, zigzag_thick], center=true);
                translate([x2, y, z + zigzag_period]) cube([zigzag_thick, zigzag_thick, zigzag_thick], center=true);
            }
        } else {
            hull() {
                translate([x2, y, z]) cube([zigzag_thick, zigzag_thick, zigzag_thick], center=true);
                translate([x1, y, z + zigzag_period]) cube([zigzag_thick, zigzag_thick, zigzag_thick], center=true);
            }
        }
    }
}

// Zigzag sur face Y
module zigzag_y(y1, y2, x, z0, z1, side) {
    n = floor((z1 - z0) / zigzag_period);
    for (i = [0 : n-1]) {
        z = z0 + i * zigzag_period;
        if (i % 2 == 0) {
            hull() {
                translate([x, y1, z]) cube([zigzag_thick, zigzag_thick, zigzag_thick], center=true);
                translate([x, y2, z + zigzag_period]) cube([zigzag_thick, zigzag_thick, zigzag_thick], center=true);
            }
        } else {
            hull() {
                translate([x, y2, z]) cube([zigzag_thick, zigzag_thick, zigzag_thick], center=true);
                translate([x, y1, z + zigzag_period]) cube([zigzag_thick, zigzag_thick, zigzag_thick], center=true);
            }
        }
    }
}

// ===============================================
// PIÈCE 4 : V TOP + BARRE GOPRO
// ===============================================

module v_top() {
    y_inner_r = arch_y_inner_pos - bar_d/2;
    y_inner_l = -(arch_y_inner_pos - bar_d/2);
    gopro_bar_y_len = arch_y_inner_pos * 0.6;

    difference() {
        union() {
            // Bras V (noir)
            color(c_main) {
                hull() {
                    translate([0, y_inner_r, arch_top_z - v_thickness])
                        cube([v_thickness, bar_d, v_thickness], center=true);
                    translate([0, gopro_bar_y_len/2, arch_top_z + v_rise])
                        cube([v_thickness, v_thickness, v_thickness], center=true);
                }
                hull() {
                    translate([0, y_inner_l, arch_top_z - v_thickness])
                        cube([v_thickness, bar_d, v_thickness], center=true);
                    translate([0, -gopro_bar_y_len/2, arch_top_z + v_rise])
                        cube([v_thickness, v_thickness, v_thickness], center=true);
                }
            }

            // Barre GoPro (noir)
            color(c_main)
            translate([0, 0, arch_top_z + v_rise])
                minkowski() {
                    cube([gopro_bar_sec - 4, gopro_bar_y_len - 4, gopro_bar_sec - 4], center=true);
                    sphere(2);
                }

            // Vis 1/4" GoPro (orange) — juste le repère visuel, la vis passe par le dessous
            color(c_accent)
            translate([0, 0, arch_top_z + v_rise + gopro_bar_sec/2])
                cylinder(h=3, d=gopro_screw_diam + 4);

            // Orange accent ring
            color(c_accent)
            translate([0, 0, arch_top_z + v_rise])
                difference() {
                    cube([gopro_bar_sec + 2, gopro_bar_y_len + 2, 2], center=true);
                    cube([gopro_bar_sec - 2, gopro_bar_y_len - 2, 3], center=true);
                }
        }

        // Trou 1/4" traversant pour vis GoPro (du bas vers le haut)
        translate([0, 0, arch_top_z + v_rise - gopro_bar_sec])
            cylinder(h=gopro_bar_sec*2 + 10, d=gopro_screw_diam);

        // Fraisage tête vis 1/4" en dessous de la barre
        translate([0, 0, arch_top_z + v_rise - gopro_bar_sec/2 - 1])
            cylinder(h=bolt_head_depth + 1, d=12);

        // Trou vis poignée → V (M3 horizontal, plus bas que GoPro)
        translate([-gopro_bar_sec, 0, arch_top_z + v_rise + 3])
            rotate([0, 90, 0])
                cylinder(h=gopro_bar_sec*2, d=bolt_diam);
        // Piège écrou côté +X du V
        translate([gopro_bar_sec/2 - nut_depth, 0, arch_top_z + v_rise + 3])
            rotate([0, 90, 0])
                cylinder(h=nut_depth + 0.5, d=nut_w, $fn=6);
    }
}

// ===============================================
// PIÈCE 5 : POIGNÉE
// ===============================================

module handle() {
    hx = -hol_l/2 - handle_offset - handle_depth;
    grip_bottom_z = hol_h + 10;
    grip_cx = hx + handle_depth/2;  // Centre X du grip à la base

    // Position réelle du haut du grip après tilt
    grip_top_x = grip_cx + sin(handle_tilt) * handle_grip_len;
    grip_top_z = grip_bottom_z + cos(handle_tilt) * handle_grip_len;

    // Position beaver tail
    bt_x = grip_top_x - beaver_tail_d/2;
    bt_z = grip_top_z + beaver_tail_h;

    difference() {
        union() {
            // === ZONE GRIP ERGONOMIQUE (profil pistolet inversé) ===
            color(c_main)
            translate([grip_cx, 0, grip_bottom_z])
                rotate([0, handle_tilt, 0])
                    ergo_grip(handle_grip_len);

            // === BEAVER TAIL (extension haute, fourche pouce/index) ===
            color(c_main)
            hull() {
                // Haut du grip (position réelle après tilt)
                translate([grip_top_x, 0, grip_top_z])
                    rotate([0, handle_tilt, 0])
                        scale([1.1, 0.9, 1])
                            cylinder(h=1, d=handle_depth, center=true);
                // Extension vers l'arrière
                translate([bt_x, 0, bt_z])
                    scale([1.3, 0.8, 1])
                        sphere(d=handle_depth * 0.7);
            }

            // === STRUT HAUTE -> côté V bar (fine) ===
            color(c_main)
            hull() {
                translate([bt_x, 0, bt_z])
                    sphere(d=bar_w);
                translate([-gopro_bar_sec/2, -bar_w/2, arch_top_z + v_rise + 2])
                    cube([1, bar_w, gopro_bar_sec - 4]);
            }

            // === BARRE BASSE -> holder (fine) ===
            color(c_main)
            hull() {
                translate([grip_cx, 0, grip_bottom_z])
                    rotate([0, handle_tilt, 0])
                        cylinder(h=1, d=bar_w, center=true);
                translate([-hol_l/2 - wall, -bar_w/2, hol_h/2 - bar_w/2])
                    cube([wall, bar_w, bar_w]);
            }

            // === ORANGE GRIP TEXTURE (bande centrale) ===
            color(c_accent)
            translate([grip_cx, 0, grip_bottom_z + handle_grip_len * 0.2])
                rotate([0, handle_tilt, 0])
                    difference() {
                        scale([1.02, 1.02, 1])
                            ergo_grip_shell(handle_grip_len * 0.5);
                        ergo_grip_shell(handle_grip_len * 0.5 + 1);
                    }
        }

        // Trous vis poignée → base (M3 horizontal)
        for (dy = [-handle_width/4, handle_width/4]) {
            translate([-base_l/2 - 5, dy, hol_h/2])
                rotate([0, 90, 0])
                    cylinder(h=handle_offset + handle_depth + 10, d=bolt_diam);
            translate([hx - 1, dy, hol_h/2])
                rotate([0, 90, 0])
                    cylinder(h=bolt_head_depth + 1, d=bolt_head_diam);
        }

        // Trou vis poignée → côté V (M3 horizontal)
        translate([hx - 1, 0, arch_top_z + v_rise + 3])
            rotate([0, 90, 0])
                cylinder(h=-hx + gopro_bar_sec/2 + 2, d=bolt_diam);
        translate([hx - 1, 0, arch_top_z + v_rise + 3])
            rotate([0, 90, 0])
                cylinder(h=bolt_head_depth + 1, d=bolt_head_diam);
    }
}

// Profil grip ergonomique — renflement central, affiné haut/bas, méplat avant
module ergo_grip(len) {
    n = 20;
    for (i = [0 : n-1]) {
        t = i / n;
        z = t * len;
        // Renflement parabolique : max au centre, min aux extrémités
        bulge = handle_bulge * (1 - pow(2*t - 1, 2));
        d_x = handle_depth + bulge;
        d_y = handle_width + bulge * 0.5;

        hull() {
            translate([0, 0, z])
                resize([d_x, d_y, 0])
                    cylinder(h=0.01, d=handle_depth, center=true);
            translate([0, 0, z + len/n])
                resize([d_x, d_y, 0]) {
                    nt = (i+1)/n;
                    nb = handle_bulge * (1 - pow(2*nt - 1, 2));
                    cylinder(h=0.01, d=handle_depth, center=true);
                }
        }
    }

    // Méplat avant (face phalanges, côté +X) — légère courbe aplatie
    translate([handle_depth/2 - 2, 0, len/2])
        cube([2, handle_width * 0.7, len * 0.8], center=true);
}

// Shell version pour la texture orange
module ergo_grip_shell(len) {
    n = 10;
    for (i = [0 : n-1]) {
        t = i / n;
        z = t * len;
        bulge = handle_bulge * (1 - pow(2*t - 1, 2));
        d_x = handle_depth + bulge;
        d_y = handle_width + bulge * 0.5;
        hull() {
            translate([0, 0, z])
                resize([d_x, d_y, 0])
                    cylinder(h=0.01, d=handle_depth, center=true);
            translate([0, 0, z + len/n])
                resize([d_x, d_y, 0])
                    cylinder(h=0.01, d=handle_depth, center=true);
        }
    }
}

// ===============================================
// PIÈCE 6 : LIDAR — PLATINE + CROSSBAR + PIED
// Une seule pièce imprimée
// ===============================================

module lidar_mount() {
    // Position centre platine LiDAR (avancée vers +X)
    plx = lidar_forward_offset;
    ply = lidar_center_y;
    plz = lidar_mount_z;

    // Position pied sur la base
    foot_x = lidar_forward_offset;
    foot_y = lidar_center_y;
    foot_z = hol_h;

    difference() {
        union() {
            // === PLATINE CIRCULAIRE inclinée 30° avec 4 trous M3 en + ===
            color(c_main)
            translate([plx, ply, plz])
                rotate([0, lidar_tilt, 0])
                    cylinder(h=lidar_plate_thick, d=lidar_plate_size, center=true);

            // === CROSSBAR entre les deux arches (en dessous de la platine) ===
            crossbar_z = plz - bar_w * 1.5;
            color(c_main)
            hull() {
                translate([arch_bx2, arch_y_inner_pos, crossbar_z])
                    cube([bar_w, bar_d, bar_w], center=true);
                translate([arch_bx2, -arch_y_inner_pos, crossbar_z])
                    cube([bar_w, bar_d, bar_w], center=true);
            }

            // === BRAS crossbar → platine ===
            color(c_main)
            hull() {
                translate([arch_bx2, 0, crossbar_z])
                    cube([bar_w, bar_d, bar_w], center=true);
                translate([plx, ply, plz])
                    rotate([0, lidar_tilt, 0])
                        translate([0, 0, -lidar_plate_thick/2])
                            cylinder(h=2, d=20, center=true);
            }

            // === PIED DE RENFORT → base ===
            color(c_main)
            hull() {
                // Bas du pied (sur le dessus de la base)
                translate([foot_x, foot_y, foot_z])
                    cube([bar_w, bar_w, bar_w], center=true);
                // Haut du pied (sous la platine)
                translate([plx, ply, plz])
                    rotate([0, lidar_tilt, 0])
                        translate([0, 0, -lidar_plate_thick/2])
                            cylinder(h=2, d=20, center=true);
            }
            // Renfort diagonal crossbar → pied
            crossbar_z2 = plz - bar_w * 1.5;
            color(c_main)
            hull() {
                translate([arch_bx2, ply, crossbar_z2])
                    cube([bar_w, bar_d, bar_w], center=true);
                translate([foot_x, foot_y, foot_z])
                    cube([bar_w, bar_w, bar_w], center=true);
            }
        }

        // === TROUS VIS M3 LIDAR (4 en +, sur la platine inclinée) ===
        translate([plx, ply, plz])
            rotate([0, lidar_tilt, 0]) {
                // 4 vis en croix +
                for (angle = [0, 90, 180, 270]) {
                    rotate([0, 0, angle])
                        translate([lidar_bolt_radius, 0, 0]) {
                            // Trou traversant
                            cylinder(h=lidar_plate_thick + 2, d=bolt_diam, center=true);
                            // Fraisage tête en dessous (côté +Z = dessous car platine vue du bas)
                            translate([0, 0, lidar_plate_thick/2 - bolt_head_depth])
                                cylinder(h=bolt_head_depth + 1, d=bolt_head_diam);
                        }
                }
            }

        // === TROUS VIS CROSSBAR → ARCHES (M3 horizontal) ===
        crossbar_z3 = plz - bar_w * 1.5;
        for (side = [1, -1]) {
            translate([arch_bx2, side * arch_y_inner_pos, crossbar_z3])
                rotate([90, 0, 0])
                    cylinder(h=bar_d*2, d=bolt_diam, center=true);
            translate([arch_bx2, side * (arch_y_inner_pos - bar_d/2), crossbar_z3])
                rotate([90 * side, 0, 0])
                    cylinder(h=bolt_head_depth + 1, d=bolt_head_diam);
        }

        // === TROU VIS PIED → BASE (M3 vertical, tête en bas) ===
        translate([foot_x, foot_y, foot_z - 5])
            cylinder(h=bar_w + 10, d=bolt_diam);
        translate([foot_x, foot_y, foot_z - bar_w/2 - 0.01])
            cylinder(h=bolt_head_depth, d=bolt_head_diam);
    }
}

// ===============================================
// ASSEMBLAGE / SÉLECTEUR DE PIÈCE
// ===============================================

if (part == "all") {
    rpi_holder();
    arch(1);
    arch(-1);
    arch_cap(1);
    arch_cap(-1);
    v_top();
    lidar_mount();
    handle();
}

if (part == "base")        rpi_holder();
if (part == "base_bottom") base_bottom();
if (part == "base_top")    base_top();
if (part == "arch_r")      arch(1);
if (part == "arch_l")      arch(-1);
if (part == "cap_r")       arch_cap(1);
if (part == "cap_l")       arch_cap(-1);
if (part == "v_top")       v_top();
if (part == "handle")      handle();
if (part == "lidar")       lidar_mount();
