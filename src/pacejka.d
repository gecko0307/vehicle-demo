/*
Copyright (c) 2022 Timur Gafarov

Boost Software License - Version 1.0 - August 17th, 2003

Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/
module pacejka;

import std.math;
import dlib.math.utils;

/**
 * Pacejka '94 (Magic Formula) tyre friction model
 */
struct PacejkaModel
{
    float a0 = 1.5f;    // Shape factor (1.4..1.8)
    float a1 = -22.0f;  // Load influence on lateral friction coefficient, 1/kN (-80..+80)
    float a2 = 1600.0f; //1011.0f; // Lateral friction coefficient (900..1700)
    float a3 = 1078.0f; // Change of stiffness with slip, N/deg (500..2000)
    float a4 = 1.82f;   // Change of progressivity of stiffness / load, 1/kN (0..50)
    float a5 = 0.208f;  // Camber influence on stiffness, %/deg/100 (-0.1..+0.1)
    float a6 = 0.0f;    // Curvature change with load (-2..+2)
    float a7 = -0.3f;   // Curvature factor (-20..+1)
    float a8 = 0.0f;    // Load influence on horizontal shift, deg/kN (-1..+1)
    float a9 = 0.0f;    // Horizontal shift at load = 0 and camber = 0, deg (-1..+1)
    float a10 = 0.0f;   // Camber influence on horizontal shift, deg/deg (-0.1..+0.1)
    float a11 = 0.0f;   // Vertical shift, N (-200..+200)
    float a12 = 0.0f;   // Vertical shift at load, N = 0 (-10..+10)
    float a13 = 0.0f;   // Camber influence on vertical shift, load dependent, N/deg/kN (-10..+10)
    float a14 = 0.0f;   // Camber influence on vertical shift, N/deg (-15..+15)
    float a15 = 0.0f;   // Camber influence on lateral friction coefficient, 1/deg (-0.01..+0.01)
    float a16 = 0.0f;   // Curvature change with camber (-0.1..+0.1)
    float a17 = 0.5f;   // Curvature shift (-1..+1)
    
    float lateralForce(float normalForce, float slipAngle, float camberAngle)
    {
        if (normalForce == 0.0f || slipAngle == 0.0f)
            return 0.0f;
        
        float load = normalForce * 0.001f; // to kN
        float slipAngleDeg = radtodeg(slipAngle);
        float camberAngleDeg = radtodeg(camberAngle);
        
        float C = a0;
        float D = load * (a1 * load + a2) * (1.0f - a15 * pow(camberAngleDeg, 2.0));
        float BCD = a3 * sin(atan(load / a4) * 2.0f) * (1.0f - a5 * abs(camberAngleDeg));
        float B = BCD / (C * D);
        float H = a8 * load + a9 + a10 * camberAngleDeg;
        float E = (a6 * load + a7) * (1.0f - (a16 * camberAngleDeg + a17) * sign(slipAngleDeg + H));
        float V = a11 * load + a12 + (a13 * load + a14) * camberAngleDeg * load;
        float Bx1 = B * (slipAngleDeg + H);
        float F = D * sin(C * atan(Bx1 - E * (Bx1 - atan(Bx1)))) + V;
        
        return F;
    }
    
    float b0 = 1.65f;   // Shape factor (1.4..1.8)
    float b1 = -21.0f;  // Load influence on longitudinal friction coefficient, 1/kN (-80..+80)
    float b2 = 1144.0f; // Longitudinal friction coefficient (900..1700)
    float b3 = 49.0f;   // Curvature factor of stiffness/load, N/%/kN^2 (-20..+20)
    float b4 = 226.0f;  // Change of stiffness with slip, N/% (100..500)
    float b5 = -0.1f;   // Change of progressivity of stiffness/load, 1/kN (-1..+1)
    float b6 = 0.0f;    // Curvature change with load^2 (-0.1..+0.1)
    float b7 = 0.1f;    // Curvature change with load (-1..+1)
    float b8 = -5.0f;   // Curvature factor (-20..+1)
    float b9 = 0.0f;    // Load influence on horizontal shift, %/kN (-1..+1)
    float b10 = 0.0f;   // Horizontal shift, % (-5..+5)
    float b11 = 0.0f;   // Vertical shift, N (-100..+100)
    float b12 = 0.0f;   // Vertical shift at load = 0, N (-10..+10)
    float b13 = 0.0f;   // Curvature shift (-1..+1)
    
    float longitudinalForce(float normalForce, float slipRatio)
    {
        if (normalForce == 0.0f || slipRatio == 0.0f)
            return 0.0f;
        
        float load = normalForce * 0.001f; // to kN
        float loadSquared = load * load;
        
        float C = b0;
        float D = load * (b1 * load + b2);
        float BCD = (b3 * loadSquared + b4 * load) * exp(-b5 * load);
        float B = BCD / (C * D);
        float H = b9 * load + b10;
        float E = (b6 * loadSquared + b7 * load + b8) * (1.0f - b13 * sign(slipRatio + H));
        float V = b11 * load + b12;
        float Bx1 = B * (slipRatio + H);
        float F = D * sin(C * atan(Bx1 - E * (Bx1 - atan(Bx1)))) + V;
        
        return F;
    }
}
