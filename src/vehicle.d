module vehicle;

import std.stdio;
import std.algorithm;
import std.math;
import dagon;
import dagon.ext.newton;
import pacejka;

struct Suspension
{
    float minLength;
    float maxLength;
    float stiffness; 
    float damping;
    float compression;
    float length;
    float lengthPrev;
}

class Wheel: Owner, NewtonRaycaster
{
    Vehicle vehicle;
    Vector3f position = Vector3f(0.0f, 0.0f, 0.0f);
    Suspension suspension;
    float radius = 0.35f;
    float steeringAngle = 0.0f;
    float camberAngle = 0.0f;
    float facing = 0.0f;
    float normalForce = 0.0f;
    float tractionForce = 0.0f;
    float lateralFrictionForce = 0.0f;
    float staticLateralFrictionForce = 0.0f;
    float longitudinalFrictionForce = 0.0f;
    float load = 0.25f;
    float slipAngle = 0.0f;
    float slipRatio = 0.0f;
    float torque = 0.0f;
    float torqueSplitRatio = 0.0f;
    float angularVelocity = 0.0f;
    float roll = 0.0f;
    float invInertia = 0.8f;
    float staticFrictionCoefficient = 0.99f;
    float lateralDynamicFrictionCoefficient = 0.75f;
    float longitudinalDynamicFrictionCoefficient = 1.0f;
    Quaternionf steering = Quaternionf.identity;
    bool brake = false;
    
    float maxRayDistance = 1000.0f;
    protected float closestHitRayParam = 1.0f;
    Vector3f groundPosition;
    Vector3f groundNormal;
    bool onGround = false;
    
    PacejkaModel tyreModel;
    
    this(Vector3f position, float facing, Vehicle vehicle)
    {
        super(vehicle);
        this.vehicle = vehicle;
        this.position = position;
        this.facing = facing;
        
        suspension.minLength = 0.2f;
        suspension.maxLength = 0.3f;
        suspension.stiffness = 100.0f;
        suspension.damping = 10.0f;
        suspension.compression = 0.0f;
        suspension.length = 0.0f;
        suspension.lengthPrev = 0.0f;
    }
    
    float onRayHit(NewtonRigidBody nbody, Vector3f hitPoint, Vector3f hitNormal, float t)
    {
        if (t < closestHitRayParam)
        {
            groundPosition = hitPoint;
            groundNormal = hitNormal;
            closestHitRayParam = t;
            return t;
        }
        else
        {
            return 1.0f;
        }
    }
    
    bool raycast(Vector3f pstart, Vector3f pend)
    {
        closestHitRayParam = 1.0f;
        vehicle.world.raycast(pstart, pend, this);
        groundPosition = pstart + (pend - pstart).normalized * maxRayDistance * closestHitRayParam;
        return (closestHitRayParam < 1.0f);
    }
    
    void update(double dt)
    {
        Vector3f upVectorWorld = verticalAxis();
        Vector3f rayDir = -upVectorWorld;
        Vector3f suspPosition = position * vehicle.chassisBody.transformation;
        
        steering = rotationQuaternion!float(Axis.y, degtorad(steeringAngle));
        
        Vector3f forwardAxis = longitudinalAxis();
        Vector3f sideAxis = lateralAxis();
        Vector3f forcePosition = tyreContactPoint();
        
        bool hitGround = raycast(suspPosition, suspPosition + rayDir * maxRayDistance);
        float suspToGround = distance(suspPosition, groundPosition);
        
        float angularAcceleration = 0.0f;
        
        if (!hitGround || (suspToGround > suspension.maxLength + radius)) // wheel is in air
        {
            onGround = false;
            
            suspension.lengthPrev = suspension.maxLength;
            suspension.length = suspension.maxLength;
            suspension.compression = 0.0f;
            
            normalForce = 0.0f;
            tractionForce = 0.0f;
            lateralFrictionForce = 0.0f;
            longitudinalFrictionForce = 0.0f;
            
            slipAngle = 0.0f;
            slipRatio = 0.0f;
            
            angularVelocity = torque / radius * invInertia * dt;
        }
        else // suspension is compressed
        {
            onGround = true;
            
            suspension.lengthPrev = suspension.length;
            suspension.length = max(0.0f, suspToGround - radius);
            suspension.compression = suspension.maxLength - suspension.length;
            
            // Normal force
            float wheelLoad = vehicle.chassisBody.mass * load;
            float springForce = suspension.compression * suspension.stiffness;
            float compressionSpeed = suspension.lengthPrev - suspension.length;
            float dampingForce = (compressionSpeed * suspension.damping) / dt;
            normalForce = (springForce + dampingForce) * wheelLoad;
            
            vehicle.chassisBody.addForceAtPos(groundNormal * normalForce, forcePosition);
            
            float chassisSpeed = vehicle.speed;
            Vector3f chassisVelocity = vehicle.velocity;
            Vector3f tyreVelocity = vehicle.chassisBody.pointVelocity(forcePosition);
            float lateralSpeed = dot(tyreVelocity, sideAxis);
            float longitudinalDir = (dot(vehicle.chassisBody.velocity.normalized, forwardAxis) > 0.0f) ? 1.0f : -1.0f;
            
            float longitudinalSpeed = dot(tyreVelocity, forwardAxis);
            
            if (brake)
            {
                // Block the wheel
                angularAcceleration = 0.0f;
                angularVelocity = 0.0f;
                slipRatio = 1.0f;
            }
            else if (abs(torque) > 0.0f)
            {
                // Apply torque
                tractionForce = torque / radius * vehicle.roadGrip * invInertia;
                vehicle.chassisBody.addForceAtPos(forwardAxis * tractionForce, forcePosition);
                angularAcceleration = tractionForce * 0.2f * dt;
                longitudinalSpeed -= angularVelocity * radius;
                slipRatio = clamp(abs((angularVelocity * radius) / max2(abs(longitudinalSpeed), 0.00001f)), 0.0f, 1.0f);
            }
            else
            {
                // Free spin
                angularVelocity = longitudinalSpeed / radius * invInertia;
                angularAcceleration = 0.0f;
                slipRatio = 0.0f;
            }
            
            slipAngle = atan2(lateralSpeed, abs(longitudinalSpeed));
            
            // Friction force
            float idleThreshold = 0.5f;
            // speedFactor interpolates between static (0.0) and dynamic (1.0) friction
            float speedFactor = clamp(chassisSpeed / idleThreshold, 0.0f, 1.0f);
            float staticLateralFrictionForce = lateralSpeed / dt * wheelLoad * staticFrictionCoefficient;
            float dynamicLateralFrictionForce = tyreModel.lateralForce(normalForce, slipAngle, degtorad(clamp(camberAngle, -4.0f, 4.0f))) * lateralDynamicFrictionCoefficient;
            lateralFrictionForce = lerp(staticLateralFrictionForce, dynamicLateralFrictionForce, speedFactor);
            longitudinalFrictionForce = tyreModel.longitudinalForce(normalForce, slipRatio) * longitudinalDynamicFrictionCoefficient;
            vehicle.chassisBody.addForceAtPos(-sideAxis * lateralFrictionForce, forcePosition);
            vehicle.chassisBody.addForceAtPos(-forwardAxis * longitudinalDir * longitudinalFrictionForce, forcePosition);
        }
        
        angularVelocity += angularAcceleration * dt;
        
        float angularVelocityVisual = clamp(angularVelocity, -15.0f, 15.0f);
        roll += angularVelocityVisual * dt;
        roll = fmod(roll, 2.0f * PI);
    }
    
    Vector3f tyreContactPoint() const
    {
        Vector3f tyreBottom = position - Vector3f(0.0f, suspension.length + radius, 0.0f);
        return tyreBottom * vehicle.chassisBody.transformation;
    }
    
    Vector3f verticalAxis()
    {
        return vehicle.verticalAxis;
    }
    
    Vector3f lateralAxis()
    {
        return steering.rotate(vehicle.lateralAxis * facing).normalized;
    }
    
    Vector3f longitudinalAxis()
    {
        return steering.rotate(vehicle.longitudinalAxis).normalized;
    }
    
    float getLateralFrictionForce()
    {
        Vector3f wheelVelocity = vehicle.chassisBody.pointVelocity(tyreContactPoint);
        float lateralSpeed = abs(dot(wheelVelocity, lateralAxis));
        return lerp(10000.0f, 5000.0f, clamp((lateralSpeed - 2.0f) / (8.0f - 2.0f), 0.0f, 1.0f));
    }
    
    float getLongitudinalFrictionForce()
    {
        return 100.0f;
    }
    
    Vector3f localWheelPosition()
    {
        return position - Vector3f(0.0f, suspension.length, 0.0f);
    }
    
    Quaternionf localRotation()
    {
        float facingAngle = 90.0f - 90.0f * facing;
        return
            rotationQuaternion!float(Axis.y, degtorad(facingAngle + steeringAngle)) *
            rotationQuaternion!float(Axis.z, degtorad(-camberAngle)) *
            rotationQuaternion!float(Axis.x, roll * facing);
    }
}

Vector3f boxInertia(Vector3f halfSize, float mass)
{
    float x2 = halfSize.x * halfSize.x;
    float y2 = halfSize.y * halfSize.y;
    float z2 = halfSize.z * halfSize.z;
    float Ixx = (mass / 3.0) * (y2 + z2);
    float Iyy = (mass / 3.0) * (x2 + z2);
    float Izz = (mass / 3.0) * (x2 + y2);
    return Vector3f(Ixx, Iyy, Izz);
}

class Vehicle: EntityComponent
{
    NewtonPhysicsWorld world;
    NewtonCollisionShape chassisShape;
    NewtonRigidBody chassisBody;
    Array!Wheel wheels;
    
    float torqueDirection = 1.0f; // -1.0f or 1.0f
    float throttle = 0.0f; // 0.0f..1.0f
    float steeringInput = 0.0f; // -1.0f..1.0f
    float maxSteeringAngle = 45.0f;
    float maxTorque = 5000.0f;
    
    bool accelerating = false;
    bool brake = false;
    
    float movementDirection = 0.0f;
    
    float roadGrip = 0.75f;
    
    Matrix4x4f prevTransformation;
    
    this(NewtonPhysicsWorld world, Entity entity, NewtonCollisionShape shape, float mass, int materialID)
    {
        super(world.eventManager, entity);
        this.world = world;
        
        this.chassisShape = shape;
        
        this.chassisBody = world.createDynamicBody(this.chassisShape, mass);
        this.chassisBody.position = entity.position;
        this.chassisBody.rotation = entity.rotation;
        this.chassisBody.transformation =
            translationMatrix(entity.position) *
            entity.rotation.toMatrix4x4;
        this.chassisBody.raycastable = false;
        this.chassisBody.groupId = materialID;
        
        NewtonBodySetContinuousCollisionMode(chassisBody.newtonBody, 1);
        NewtonBodySetMatrix(chassisBody.newtonBody, chassisBody.transformation.arrayof.ptr);
        
        NewtonMaterialSetDefaultFriction(world.newtonWorld, 0, materialID, 0.2f, 0.2f);
        NewtonMaterialSetDefaultElasticity(world.newtonWorld, 0, materialID, 0.2f);
        
        prevTransformation = Matrix4x4f.identity;
    }
    
    ~this()
    {
        wheels.free();
    }
    
    Wheel addWheel(Vector3f suspensionPosition, float radius, float facing)
    {
        Wheel wheel = New!Wheel(suspensionPosition, facing, this);
        wheel.radius = radius;
        wheels.append(wheel);
        return wheel;
    }
    
    void setInertia(float mass, Vector3f itertia)
    {
        NewtonBodySetMassMatrix(chassisBody.newtonBody, mass, itertia.x, itertia.y, itertia.z);
    }
    
    Vector3f position() @property
    {
        return chassisBody.position.xyz;
    }
    
    Quaternionf rotation() @property
    {
        return chassisBody.rotation;
    }
    
    Matrix4x4f transformation() @property
    {
        return chassisBody.transformation;
    }
    
    Vector3f longitudinalAxis()
    {
        return chassisBody.transformation.forward;
    }
    
    Vector3f lateralAxis()
    {
        return chassisBody.transformation.right;
    }
    
    Vector3f verticalAxis()
    {
        return chassisBody.transformation.up;
    }
    
    Vector3f velocity() @property
    {
        return chassisBody.velocity;
    }
    
    float speed() @property
    {
        return chassisBody.velocity.length;
    }
    
    float speedKMH() @property
    {
        return chassisBody.velocity.length * 3.6;
    }
    
    void accelerate(float direction, float delta)
    {
        brake = (movementDirection < 0.0f && direction > 0.0f) ||
                (movementDirection > 0.0f && direction < 0.0f);
        
        torqueDirection = direction;
        
        if (throttle < 1.0f)
            throttle += delta;
        else
            throttle = 1.0f;
        
        accelerating = true;
    }
    
    void idle()
    {
        accelerating = false;
        brake = false;
    }
    
    void steer(float input)
    {
        steeringInput += input;
        
        if (steeringInput > 1.0f)
            steeringInput = 1.0f;
        if (steeringInput < -1.0f)
            steeringInput = -1.0f;
    }
    
    float lateralSpeedKMH() @property
    {
        Vector3f rightVector = chassisBody.transformation.right;
        return abs(dot(chassisBody.velocity, rightVector)) * 3.6;
    }
    
    float longitudinalSpeedKMH() @property
    {
        Vector3f forwardVector = chassisBody.transformation.forward;
        return abs(dot(chassisBody.velocity, forwardVector)) * 3.6;
    }
    
    float lateralSlip() @property
    {
        float lateralSpeed = abs(dot(chassisBody.velocity, chassisBody.transformation.right));
        return clamp((lateralSpeed - 6.0f) / 6.0f, 0.0f, 1.0f);
    }
    
    float longitudinalSlip() @property
    {
        if (brake) return 1.0f;
        
        float res = 0.0f;
        foreach(wheel; wheels)
        {
            if (wheel.onGround)
            {
                res += clamp(wheel.slipRatio, 0.0f, 1.0f);
            }
        }
        return res / wheels.length;
    }
    
    override void update(Time t)
    {
        float ackermann = 5.0f;
        float steeringAngleInner = maxSteeringAngle * steeringInput;
        float steeringAngleOuter = (maxSteeringAngle - ackermann) * steeringInput;
        
        if (steeringInput < 0.0f)
        {
            wheels[0].steeringAngle = steeringAngleInner;
            wheels[1].steeringAngle = steeringAngleOuter;
        }
        else
        {
            wheels[0].steeringAngle = steeringAngleOuter;
            wheels[1].steeringAngle = steeringAngleInner;
        }
        
        float torque = 0.0f;
        if (accelerating)
        {
            float spd = speedKMH;
            float decreaseFactor = lerp(1.0f, 0.9f, clamp((spd - 80.0f) / (200.0f - 80.0f), 0.0f, 1.0f));
            torque = maxTorque * decreaseFactor * throttle * torqueDirection;
        }
        
        foreach(w; wheels)
        {
            w.torque = torque * w.torqueSplitRatio;
            w.brake = brake;
            w.update(t.delta);
        }
        
        chassisBody.update(t.delta);

        entity.prevTransformation = prevTransformation;

        entity.position = chassisBody.position.xyz;
        entity.transformation = chassisBody.transformation * scaleMatrix(entity.scaling);
        entity.invTransformation = entity.transformation.inverse;
        entity.rotation = chassisBody.rotation;

        entity.absoluteTransformation = entity.transformation;
        entity.invAbsoluteTransformation = entity.invTransformation;
        entity.prevAbsoluteTransformation = entity.prevTransformation;

        prevTransformation = entity.transformation;
        
        float steeringDecreaseStep = 2.0f * t.delta;
        if (steeringInput > steeringDecreaseStep)
            steeringInput -= steeringDecreaseStep;
        else if (steeringInput < -steeringDecreaseStep)
            steeringInput += steeringDecreaseStep;
        else
            steeringInput = 0.0f;
        
        movementDirection = (dot(velocity.normalized, longitudinalAxis) < 0.0f)? -1.0f : 1.0f;
        
        if (!accelerating)
        {
            if (throttle > 0.0f)
                throttle -= t.delta;
            else
                throttle = 0.0f;
        }
    }
}
