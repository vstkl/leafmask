//
// Leaf Face Mask Generator for an imported head STL
// -------------------------------------------------
// Usage:
// 1) Put this .scad file in the same folder as head.stl
// 2) Open in OpenSCAD (2021+ recommended).
// 3) Adjust the "User Controls" to align your head model and clip the face region.
// 4) Render (F6). Note: minkowski on meshes is heavy; start with low detail, small regions.
// 5) Export STL of `LEAF_MASK()`.
//
// The mask is created by:
//  - Clipping a front "face section" of the head
//  - Creating a clearance shell using minkowski "inflate"
//  - Intersecting that shell with a field of overlapping leaf "plates"
//
// Tip: Start with a small `face_w`, `face_h`, and a shallow `clip_depth` to iterate quickly,
// then increase once you’re happy with the placement.
//
// -------------------------------------------------
//               USER CONTROLS
// -------------------------------------------------

// Placement of the imported head
head_scale      = 1.0;            // overall scale factor for head.stl
head_rot        = [0,0,0];        // [rx, ry, rz] in degrees
head_translate  = [0,0,0];        // [x,y,z] mm

// Region of the face to capture (a front-facing rectangular prism)
face_w          = 140;            // width of face capture region (mm)
face_h          = 180;            // height of face capture region (mm)
clip_depth      = 90;             // depth of capture along +Z (mm). 0 is the clip plane at z=0.
clip_z_front    = 0;              // where the front clip plane sits (mm). You can slide this.

// Mask fit parameters
clearance       = 2.0;            // gap between head and mask inner wall (mm)
thickness       = 2.5;            // mask wall thickness (mm)
edge_bleed      = 3.0;            // how much to inset the inner clip to avoid razor-thin rims (mm)

// Leaf field parameters (the mask will "consist of" these leaves)
leaf_len        = 36;             // base leaf length (mm)
leaf_w          = 22;             // base leaf width (mm)
leaf_thick      = 3.2;            // thickness of each leaf plate before conforming (mm)
leaf_spacing    = 24;             // grid spacing for leaf placement (mm)
leaf_push       = 40;             // how far leaves extend into the face volume in -Z (mm)
leaf_twist_deg  = 20;             // extra random-like rotation variation (± deg)

// Eye openings (approximate; adjust to your head/stl)
enable_eyes     = true;           // set false to disable
eye_w           = 60;             // width of each eye cut (mm)
eye_h           = 30;             // height of each eye cut (mm)
eye_offset_x    = 35;             // half-distance between eye centers (mm)
eye_center_y    = 20;             // vertical position relative to face window center (mm)
eye_center_z    = 25;             // forward/back position for cutting (relative to clip front) (mm)

// Nose/mouth slot (optional)
enable_nose_slot = true;
nose_w          = 32;
nose_h          = 18;
nose_y          = -15;
nose_z          = 15;

// Optional side strap tabs
enable_tabs     = true;
tab_w           = 18;
tab_h           = 12;
tab_thick       = 4;
tab_offset_y    = 0;              // vertical position for tabs
tab_offset_z    = 20;             // relative to clip front

// Preview quality
$fn = 36; // increase for smoother spheres in minkowski and leaf edges

// -------------------------------------------------
//               CORE GEOMETRY
// -------------------------------------------------

// Import the head
module HEAD() {
    // Ensure head.stl is in the same folder
    translate(head_translate)
    rotate(head_rot)
    scale([head_scale, head_scale, head_scale])
        import("head.stl", convexity=10);
}

// Face clipping volumes
module FACE_CLIP_BOX(expand=0) {
    // A rectangular prism in front of the face, centered in X/Y, front plane at clip_z_front
    translate([-face_w/2 - expand, -face_h/2 - expand, clip_z_front])
        cube([face_w + 2*expand, face_h + 2*expand, clip_depth + 2*expand], center=false);
}

// Inflate a 3D object by radius r using minkowski with a sphere (approximate offset shell)
module inflate3d(r=1) {
    minkowski() {
        children();
        sphere(r=r);
    }
}

// Obtain just the front "face section" of the head
module FACE_SECTION() {
    intersection() {
        HEAD();
        FACE_CLIP_BOX();
    }
}

// Shells derived from the face section
module OUTER_SHELL() {
    // Outer shell = (face section) inflated by (clearance + thickness)
    inflate3d(r=clearance + thickness)
        FACE_SECTION();
}

module INNER_CORE() {
    // Inner core = (face section) inflated by (clearance)
    intersection() {
        inflate3d(r=clearance)
            FACE_SECTION();
        // Slightly shrink the clipping window to avoid knife-edges near perimeter
        FACE_CLIP_BOX(expand = -edge_bleed);
    }
}

module BASE_MASK() {
    difference() {
        OUTER_SHELL();
        INNER_CORE();
    }
}

// -------------------------------------------------
//               LEAF SHAPES
// -------------------------------------------------

// Simple teardrop-like leaf: built from a hull of circles; extruded into a plate
module leaf3d(len=30, wid=18, thick=3) {
    linear_extrude(height=thick)
        hull() {
            translate([0,0])     circle(d=wid);
            translate([len*0.55,0]) circle(d=wid*0.75);
            // a near-point creates a tip
            translate([len,0])   circle(d=0.1);
        }
}

// A pseudo-random rotation from integer x,y using a simple hash trick
function hash_angle(x,y,spread=leaf_twist_deg) =
    let(v = sin(x*13 + y*7)*cos(x*5 - y*11))
    v * spread;

// A field of overlapping leaves in a grid, each leaf is pushed back along -Z
module LEAF_FIELD() {
    for (x = [-face_w/2 : leaf_spacing : face_w/2])
    for (y = [-face_h/2 : leaf_spacing : face_h/2]) {
        // stagger every other row a bit
        dx = ((floor((y + face_h/2)/leaf_spacing) % 2) == 0) ? 0 : leaf_spacing*0.5;
        a  = hash_angle(x,y);
        translate([x + dx, y, clip_z_front + eye_center_z])  // near the front
            rotate([0,0,a])
                // extend backwards so intersection with shell conforms to curvature
                translate([0,0,-leaf_push])
                    leaf3d(len=leaf_len, wid=leaf_w, thick=leaf_thick + leaf_push);
    }
}

// -------------------------------------------------
//               OPENINGS & TABS
// -------------------------------------------------

module EYE_OPENINGS() {
    // Two rounded rectangular prisms that will be subtracted
    if (enable_eyes) {
        for (sx = [-1, 1]) {
            translate([sx*eye_offset_x, eye_center_y, clip_z_front + eye_center_z - 5])
                minkowski() {
                    cube([eye_w, eye_h, 12], center=true);
                    sphere(r=4);
                }
        }
    }
}

module NOSE_SLOT() {
    if (enable_nose_slot) {
        translate([0, nose_y, clip_z_front + nose_z - 5])
            minkowski() {
                cube([nose_w, nose_h, 8], center=true);
                sphere(r=3);
            }
    }
}

module STRAP_TABS() {
    if (enable_tabs) {
        // left/right tabs positioned roughly at cheek level near sides
        for (sx = [-1, 1]) {
            translate([sx*(face_w/2 + tab_w/2 - 2), tab_offset_y, clip_z_front + tab_offset_z])
                cube([tab_w, tab_h, tab_thick], center=true);
        }
    }
}

// -------------------------------------------------
//               FINAL ASSEMBLY
// -------------------------------------------------

// The mask "consisting of leaves": intersect leaves with the base shell so only the parts
// that lie on the shell remain; then subtract openings and add tabs.
module LEAF_MASK() {
    difference() {
        intersection() {
            BASE_MASK();
            union() {
                LEAF_FIELD();
                // Fill any tiny gaps with the solid base to ensure continuity
                // Comment the next line if you want strictly leaf-only (may be weaker).
                // BASE_MASK();
            }
        }
        // Openings
        EYE_OPENINGS();
        NOSE_SLOT();
    }
    // Tabs last (added back)
    STRAP_TABS();
}

// Show helpers (toggle for debugging)
show_head      = true;   // visualize the imported head
show_clip_box  = true;   // visualize the clipping window
show_base_mask = true;   // show the un-leafy shell

// Preview scene
if (show_head) color([0.8,0.8,0.8,0.4]) HEAD();
if (show_clip_box) color([1,0,0,0.2]) FACE_CLIP_BOX();
if (show_base_mask) color([0,0.6,1,0.3]) BASE_MASK();

// Export this:
LEAF_MASK();
