clear; clc;
rng(42);

%replace this with stadium-appropriate dimensions
%this one assumes the room is a rectangle
Length = 10;
Width = 10;

noGridsX = 10;
noGridsY = 10;

cellDimX = Length / noGridsX;
cellDimY = Width / noGridsY;
cellArea = cellDimX * cellDimY;

%exits
%[x_position  y_center  width] per row
%two exits on opposite walls at the same y-level
exitXLocation = Length;
exitYLocation = Width / 2;
exitWidth = 3;
numExits = 2;

exitsMatrix = [...
    exitXLocation,                exitYLocation, exitWidth; ...
    (exitXLocation - Length),     exitYLocation, exitWidth  ...
];
disp('Exit locations:');

%rectangular obstacle in the center as a placeholder stage
%defined as [xMin yMin xMax yMax]
obstacles = [3.5, 4.0, 6.5, 6.0];

%the time step
nSteps = 300;
timeperStep = 0.05;
%300 x 0.05 = 15 seconds total
settlingSteps = 30; %let agents push apart before real sim starts

%agent body
agentRadius = 0.25; %meters
agentMass = 80;     %kg
contactDiameter = 2 * agentRadius; %two agents touch at this distance

%walking/movement speed data (m/s)
lowestSpeed = 0.8;
speedMax = 1.8;
speedMaxPanic = 2.0;    %fastest desired speed at full panic
desiredSpeed = 1.34;    %Weidmann 1993 average
maxSpeedCap = 3.0;      %absolute velocity cap to prevent blowup

%force model parameters
%adapted from Helbing et al. (Nature, 2000) for dt=0.05 stability
%original Helbing uses A=2000 B=0.08 k=1.2e5 kappa=2.4e4 with dt~0.001
socialRepulsionStrength = 200;    %how hard personal space pushes (N)
socialRepulsionRange = 0.3;      %how far personal space reaches (m)
bodyCompressionStiffness = 3000; %how hard bodies resist squishing (kg/s^2)
slidingFrictionCoeff = 1500;     %how grippy body-to-body contact is (kg/(m*s))
densityForSpeedDrop = 5.4;      %density where speed drops to 37% of free speed (ped/m^2)
forceInteractionRange = 2.0;    %ignore agent pairs farther than this (m)
maxForcePerAgent = 2000;        %cap total force to prevent blowup (N)

%casualty model parameters
compressionForceToFall = 1500;  %body force (N) that causes an agent to fall
fallRecoveryTime = 999;         %fallen agents do not get back up during simulation (steps)

%panic levels
%separated from density so we can mix and match freely. Even in
%< 3 people per square meter, a highly panicked crowd can trigger chaos
panicRanges = [...
    0.0, 0.49; ...  %level A: normal to uneasy
    0.5, 0.79; ...  %level B: anxious to urgent
    0.8, 1.0   ...  %level C: panic to full panic
];
panicNames = {'LevelA', 'LevelB', 'LevelC'};

%scenario settings
%[minagents maxagents] per cell
scenarioSettings = [...
    1, 3; ...   %baseline
    4, 4; ...   %dense
    5, 10  ...  %densest
];
scenarioNames = {'Baseline', 'Dense', 'Densest'};

%each wall is a line segment [x1 y1 x2 y2]
%room boundaries have gaps cut where exits are
wallSegments = [];

%bottom and top walls (full length, no exits on these sides)
wallSegments = [wallSegments; 0 0 Length 0];
wallSegments = [wallSegments; 0 Width Length Width];

%right wall (x=Length) with gap for exit 1
exitHalfWidth1 = exitsMatrix(1,3) / 2;
exitCenter1 = exitsMatrix(1,2);
wallSegments = [wallSegments; ...
    Length, 0,                         Length, exitCenter1 - exitHalfWidth1; ...
    Length, exitCenter1 + exitHalfWidth1, Length, Width];

%left wall (x=0) with gap for exit 2
exitHalfWidth2 = exitsMatrix(2,3) / 2;
exitCenter2 = exitsMatrix(2,2);
wallSegments = [wallSegments; ...
    0, 0,                         0, exitCenter2 - exitHalfWidth2; ...
    0, exitCenter2 + exitHalfWidth2, 0, Width];

%obstacle edges become wall segments too
for obstacleIdx = 1:size(obstacles, 1)
    obsXMin = obstacles(obstacleIdx,1); obsYMin = obstacles(obstacleIdx,2);
    obsXMax = obstacles(obstacleIdx,3); obsYMax = obstacles(obstacleIdx,4);
    wallSegments = [wallSegments; ...
        obsXMin obsYMin obsXMax obsYMin; ...
        obsXMax obsYMin obsXMax obsYMax; ...
        obsXMax obsYMax obsXMin obsYMax; ...
        obsXMin obsYMax obsXMin obsYMin];
end
totalWallSegments = size(wallSegments, 1);

%% results
nScenarios = size(scenarioSettings, 1);
nPanicLevels = size(panicRanges, 1);
nCombos = nScenarios * nPanicLevels;

%columns: [totalAgents evacuated casualties avgSpeed maxPressure avgEntropy maxOverlap escapedFrac]
resultsTable = zeros(nCombos, 8);
comboLabels = cell(nCombos, 1);

%per-step histories for plotting later
histPressure   = cell(nScenarios, nPanicLevels);
histEntropy    = cell(nScenarios, nPanicLevels);
histOverlap    = cell(nScenarios, nPanicLevels);
histEvacCount  = cell(nScenarios, nPanicLevels);
histSpeed      = cell(nScenarios, nPanicLevels);
histCasualties = cell(nScenarios, nPanicLevels);

comboIdx = 0;

%%main simulation
for scenario = 1:nScenarios
    for panicLevel = 1:nPanicLevels
        comboIdx = comboIdx + 1;
        comboLabels{comboIdx} = [scenarioNames{scenario} ' x ' panicNames{panicLevel}];
        fprintf('\n=== Running: %s x %s ===\n', scenarioNames{scenario}, panicNames{panicLevel});

        perCellMin = scenarioSettings(scenario, 1);
        perCellMax = scenarioSettings(scenario, 2);
        panicLo = panicRanges(panicLevel, 1);
        panicHi = panicRanges(panicLevel, 2);

        %initialize agent data vectors
        position = [];
        agentVelocity = [];
        panicArr = [];
        baseSpeed = [];
        isFallen = [];
        nPerCell = zeros(noGridsX, noGridsY);

        for cy = 1:noGridsY
            for cx = 1:noGridsX
                nAgents = randi([perCellMin, perCellMax]);

                cellX0 = (cx - 1) * cellDimX;
                cellY0 = (cy - 1) * cellDimY;

                agentPosX = cellX0 + rand(nAgents, 1) * cellDimX;
                agentPosY = cellY0 + rand(nAgents, 1) * cellDimY;

                %random panic per agent within this panic level range
                %use rand not randi because panic is a decimal not an integer
                agentPanic = panicLo + rand(nAgents, 1) * (panicHi - panicLo);

                %random base walking speed per agent (Weidmann range)
                agentSpeed = lowestSpeed + rand(nAgents, 1) * (speedMax - lowestSpeed);

                %remove agents that landed inside an obstacle
                keep = true(nAgents, 1);
                for obstacleIdx = 1:size(obstacles, 1)
                    insideObstacle = agentPosX >= obstacles(obstacleIdx,1) & ...
                                     agentPosX <= obstacles(obstacleIdx,3) & ...
                                     agentPosY >= obstacles(obstacleIdx,2) & ...
                                     agentPosY <= obstacles(obstacleIdx,4);
                    keep = keep & ~insideObstacle;
                end
                agentPosX = agentPosX(keep); agentPosY = agentPosY(keep);
                agentPanic = agentPanic(keep); agentSpeed = agentSpeed(keep);

                nPerCell(cx, cy) = length(agentPosX);
                position = [position; agentPosX agentPosY];
                agentVelocity = [agentVelocity; zeros(length(agentPosX), 2)];
                panicArr = [panicArr; agentPanic];
                baseSpeed = [baseSpeed; agentSpeed];
                isFallen = [isFallen; false(length(agentPosX), 1)];
            end
        end

        NTotalAgents = size(position, 1);
        initialTotal = NTotalAgents;
        initialDensity = initialTotal / (Length * Width);

        fprintf('\n Agents in the Cell:\n');
        disp(nPerCell);
        fprintf('Initial Total Agents: %d\n', initialTotal);
        fprintf('Initial Density: %.2f ped/m^2\n', initialDensity);

        fprintf('First 5 agents:\n');
        for count = 1:min(5, NTotalAgents)
            fprintf('  Agent %d: pos=(%5.2f,%5.2f) panic=%.2f speed=%.2f\n', ...
                count, position(count,1), position(count,2), ...
                panicArr(count), baseSpeed(count));
        end

        %%settling
        %let agents push apart using only repulsive forces so the simulation
        %does not start with massive overlaps that blow everything up
        N = NTotalAgents;
        fprintf('  Settling for %d steps...', settlingSteps);
        for settleStep = 1:settlingSteps
            if N < 2, break; end

            %only compute repulsive forces (no driving force, no exits)
            settleForceX = zeros(N, 1);
            settleForceY = zeros(N, 1);

            %agent-agent repulsion
            pairDistX = position(:,1)' - position(:,1);
            pairDistY = position(:,2)' - position(:,2);
            pairDist = sqrt(pairDistX.^2 + pairDistY.^2);
            pairDist(1:N+1:end) = inf;

            pairNormalX = pairDistX ./ pairDist;
            pairNormalY = pairDistY ./ pairDist;

            pairOverlap = max(0, contactDiameter - pairDist);

            pairRepulsion = socialRepulsionStrength * exp((contactDiameter - pairDist) / socialRepulsionRange);
            pairRepulsion(pairDist > forceInteractionRange) = 0;
            pairCompression = bodyCompressionStiffness * pairOverlap;

            settleForceOnX = -(pairRepulsion + pairCompression) .* pairNormalX;
            settleForceOnY = -(pairRepulsion + pairCompression) .* pairNormalY;
            settleForceOnX(1:N+1:end) = 0;
            settleForceOnY(1:N+1:end) = 0;
            settleForceX = sum(settleForceOnX, 2);
            settleForceY = sum(settleForceOnY, 2);

            %wall repulsion during settling
            for wallIdx = 1:totalWallSegments
                [wallDist, wallNormX, wallNormY, ~, ~] = agentsToSegment( ...
                    position(:,1), position(:,2), ...
                    wallSegments(wallIdx,1), wallSegments(wallIdx,2), ...
                    wallSegments(wallIdx,3), wallSegments(wallIdx,4));

                notDegenerate = wallDist > 1e-6;
                wallOverlap = max(0, agentRadius - wallDist);

                wallRepulsion = socialRepulsionStrength * exp((agentRadius - wallDist) / socialRepulsionRange);
                wallCompression = bodyCompressionStiffness * wallOverlap;

                settleForceX = settleForceX + (wallRepulsion + wallCompression) .* wallNormX .* notDegenerate;
                settleForceY = settleForceY + (wallRepulsion + wallCompression) .* wallNormY .* notDegenerate;
            end

            %cap force to prevent blowup
            settleForceMag = sqrt(settleForceX.^2 + settleForceY.^2);
            forceIsTooBig = settleForceMag > maxForcePerAgent;
            if any(forceIsTooBig)
                forceScale = maxForcePerAgent ./ settleForceMag(forceIsTooBig);
                settleForceX(forceIsTooBig) = settleForceX(forceIsTooBig) .* forceScale;
                settleForceY(forceIsTooBig) = settleForceY(forceIsTooBig) .* forceScale;
            end

            %move agents apart (use agentMass for realistic settling speed)
            agentVelocity(:,1) = agentVelocity(:,1) * 0.5 + settleForceX / agentMass * timeperStep;
            agentVelocity(:,2) = agentVelocity(:,2) * 0.5 + settleForceY / agentMass * timeperStep;
            position(:,1) = position(:,1) + agentVelocity(:,1) * timeperStep;
            position(:,2) = position(:,2) + agentVelocity(:,2) * timeperStep;

            %clamp to room
            position(:,1) = max(agentRadius, min(position(:,1), Length - agentRadius));
            position(:,2) = max(agentRadius, min(position(:,2), Width - agentRadius));

            %push out of obstacles
            for obstacleIdx = 1:size(obstacles, 1)
                obsXMin = obstacles(obstacleIdx,1); obsYMin = obstacles(obstacleIdx,2);
                obsXMax = obstacles(obstacleIdx,3); obsYMax = obstacles(obstacleIdx,4);
                insideObstacle = position(:,1) > obsXMin & position(:,1) < obsXMax & ...
                                 position(:,2) > obsYMin & position(:,2) < obsYMax;
                for agentIdx = find(insideObstacle)'
                    distToEdges = [position(agentIdx,1)-obsXMin, obsXMax-position(agentIdx,1), ...
                                   position(agentIdx,2)-obsYMin, obsYMax-position(agentIdx,2)];
                    [~, nearestEdge] = min(distToEdges);
                    switch nearestEdge
                        case 1; position(agentIdx,1) = obsXMin - agentRadius;
                        case 2; position(agentIdx,1) = obsXMax + agentRadius;
                        case 3; position(agentIdx,2) = obsYMin - agentRadius;
                        case 4; position(agentIdx,2) = obsYMax + agentRadius;
                    end
                end
            end
        end
        %reset velocity after settling so everyone starts from rest
        agentVelocity = zeros(N, 2);
        %ensure isFallen is logical (concatenation with [] can cast to double)
        isFallen = logical(isFallen);
        fprintf(' done.\n');

        %initialize tracking histories
        evacuatedCount = 0;
        casualtyCount = 0;
        pressureHistory  = zeros(nSteps, 1);
        entropyHistory   = zeros(nSteps, 1);
        overlapHistory   = zeros(nSteps, 1);
        evacHistory      = zeros(nSteps, 1);
        speedHistory     = zeros(nSteps, 1);
        casualtyHistory  = zeros(nSteps, 1);

        %%time steps
        for step = 1:nSteps

            if N == 0
                break;
            end

            %find nearest exit per agent
            %each agent aims for whichever exit center is closest
            %fallen agents dont move but still take up space
            distToExits = zeros(N, numExits);
            for exitIdx = 1:numExits
                toExitX = exitsMatrix(exitIdx, 1) - position(:, 1);
                toExitY = exitsMatrix(exitIdx, 2) - position(:, 2);
                distToExits(:, exitIdx) = sqrt(toExitX.^2 + toExitY.^2);
            end
            [~, nearestExit] = min(distToExits, [], 2);

            targetX = exitsMatrix(nearestExit, 1);
            targetY = exitsMatrix(nearestExit, 2);
            dirToExitX = targetX - position(:, 1);
            dirToExitY = targetY - position(:, 2);
            distToExit = sqrt(dirToExitX.^2 + dirToExitY.^2);
            distToExit(distToExit < 1e-9) = 1;
            dirToExitX = dirToExitX ./ distToExit;
            dirToExitY = dirToExitY ./ distToExit;

            %panic jitter on direction
            %rotate by a random angle scaled by panic
            %using temp variables so we dont overwrite dirToExitX before computing Y
            jitterAngle = panicArr .* pi .* randn(N, 1);
            cosAngle = cos(jitterAngle);
            sinAngle = sin(jitterAngle);
            jitteredDirX = cosAngle .* dirToExitX - sinAngle .* dirToExitY;
            jitteredDirY = sinAngle .* dirToExitX + cosAngle .* dirToExitY;

            %local density per cell
            cellOfAgent = floor(position ./ [cellDimX cellDimY]) + 1;
            cellOfAgent = max(1, min(cellOfAgent, [noGridsX noGridsY]));
            nPerCell = zeros(noGridsX, noGridsY);
            for agentIdx = 1:N
                nPerCell(cellOfAgent(agentIdx,1), cellOfAgent(agentIdx,2)) = ...
                    nPerCell(cellOfAgent(agentIdx,1), cellOfAgent(agentIdx,2)) + 1;
            end
            localDensity = zeros(N, 1);
            for agentIdx = 1:N
                localDensity(agentIdx) = nPerCell(cellOfAgent(agentIdx,1), cellOfAgent(agentIdx,2)) / cellArea;
            end

            %desired speed per agent
            %panic boosts desired speed toward speedMaxPanic
            %density reduces it via exponential decay (Weidmann fundamental diagram)
            %fallen agents have zero desired speed (they are down)
            agentDesiredSpeed = ((1 - panicArr) .* baseSpeed + panicArr .* speedMaxPanic) ...
                                .* exp(-localDensity ./ densityForSpeedDrop);
            agentDesiredSpeed(isFallen) = 0;

            desiredVelocityX = agentDesiredSpeed .* jitteredDirX;
            desiredVelocityY = agentDesiredSpeed .* jitteredDirY;

            %relaxation time per agent (panic-dependent)
            %calm agents drift slowly (tau=5s), panicked agents snap hard (tau=0.5s)
            %this creates the documented "faster is slower" clogging effect
            relaxationTime = 0.5 * panicArr + 5.0 * (1 - panicArr);

            %agent-to-agent forces
            totalForceX = zeros(N, 1);
            totalForceY = zeros(N, 1);
            bodyForceOnAgent = zeros(N, 1); %track compression for casualty model

            if N > 1
                %pairwise vectors from agent i to agent j
                pairDistX = position(:,1)' - position(:,1);
                pairDistY = position(:,2)' - position(:,2);
                pairDist = sqrt(pairDistX.^2 + pairDistY.^2);
                pairDist(1:N+1:end) = inf; %no self-interaction on diagonal

                %unit normal (direction from i toward j) and tangent (perpendicular)
                pairNormalX = pairDistX ./ pairDist;
                pairNormalY = pairDistY ./ pairDist;
                pairTangentX = -pairNormalY;
                pairTangentY = pairNormalX;

                %how much each pair of agents overlaps (0 if not touching)
                pairOverlap = max(0, contactDiameter - pairDist);

                %social repulsion: exponential personal-space push
                %even before physical contact, people push away from each other
                pairRepulsionForce = socialRepulsionStrength * ...
                    exp((contactDiameter - pairDist) / socialRepulsionRange);
                pairRepulsionForce(pairDist > forceInteractionRange) = 0;

                %body compression: linear spring when overlapping
                %the more you squish two bodies together, the harder they push back
                pairCompressionForce = bodyCompressionStiffness * pairOverlap;

                %sliding friction: tangential drag when overlapping
                %when pressed against someone and they slide sideways, you feel drag
                %this is what makes dense crowds feel sticky and creates gridlock
                velocityDiffX = agentVelocity(:,1)' - agentVelocity(:,1);
                velocityDiffY = agentVelocity(:,2)' - agentVelocity(:,2);
                tangentialVelocityDiff = velocityDiffX .* pairTangentX + ...
                                         velocityDiffY .* pairTangentY;
                pairFrictionForce = slidingFrictionCoeff * pairOverlap .* tangentialVelocityDiff;

                %combine all three: repulsion+compression push away, friction along tangent
                pairTotalForceX = -(pairRepulsionForce + pairCompressionForce) .* pairNormalX ...
                                  + pairFrictionForce .* pairTangentX;
                pairTotalForceY = -(pairRepulsionForce + pairCompressionForce) .* pairNormalY ...
                                  + pairFrictionForce .* pairTangentY;
                pairTotalForceX(1:N+1:end) = 0;
                pairTotalForceY(1:N+1:end) = 0;

                %sum all pairwise forces on each agent
                totalForceX = sum(pairTotalForceX, 2);
                totalForceY = sum(pairTotalForceY, 2);

                %track how much compression each agent feels (for casualty model)
                %this is the total body-squishing force from all neighbors
                pairCompressionOnly = pairCompressionForce;
                pairCompressionOnly(1:N+1:end) = 0;
                bodyForceOnAgent = sum(pairCompressionOnly, 2);
            end

            %wall and obstacle forces
            %same three forces as agent-agent but against nearest wall point
            %uses agentRadius instead of contactDiameter since the wall has no body radius
            for wallIdx = 1:totalWallSegments
                [wallDist, wallNormX, wallNormY, wallTanX, wallTanY] = agentsToSegment( ...
                    position(:,1), position(:,2), ...
                    wallSegments(wallIdx,1), wallSegments(wallIdx,2), ...
                    wallSegments(wallIdx,3), wallSegments(wallIdx,4));

                notDegenerate = wallDist > 1e-6;
                wallOverlap = max(0, agentRadius - wallDist);

                %wall social repulsion
                wallRepulsionForce = socialRepulsionStrength * ...
                    exp((agentRadius - wallDist) / socialRepulsionRange);

                %wall body compression
                wallCompressionForce = bodyCompressionStiffness * wallOverlap;

                %wall sliding friction (opposes motion along the wall surface)
                agentTangentialSpeed = agentVelocity(:,1) .* wallTanX + ...
                                       agentVelocity(:,2) .* wallTanY;
                wallFrictionForce = slidingFrictionCoeff * wallOverlap .* agentTangentialSpeed;

                totalForceX = totalForceX + ((wallRepulsionForce + wallCompressionForce) .* wallNormX ...
                              - wallFrictionForce .* wallTanX) .* notDegenerate;
                totalForceY = totalForceY + ((wallRepulsionForce + wallCompressionForce) .* wallNormY ...
                              - wallFrictionForce .* wallTanY) .* notDegenerate;

                %wall compression also counts toward casualty threshold
                bodyForceOnAgent = bodyForceOnAgent + wallCompressionForce .* notDegenerate;
            end

            %cap total force per agent to prevent numerical blowup
            forceMagnitude = sqrt(totalForceX.^2 + totalForceY.^2);
            forceIsTooBig = forceMagnitude > maxForcePerAgent;
            if any(forceIsTooBig)
                forceScale = maxForcePerAgent ./ forceMagnitude(forceIsTooBig);
                totalForceX(forceIsTooBig) = totalForceX(forceIsTooBig) .* forceScale;
                totalForceY(forceIsTooBig) = totalForceY(forceIsTooBig) .* forceScale;
            end

            % casualty check
            %agents under extreme compression fall and become immobile obstacles
            %based on Fruin (1993) compression tolerance and Yi et al. (2020) tumble concept
            newlyFallen = ~isFallen & (bodyForceOnAgent > compressionForceToFall);
            if any(newlyFallen)
                isFallen(newlyFallen) = true;
                casualtyCount = casualtyCount + sum(newlyFallen);
                %fallen agents stop moving immediately
                agentVelocity(newlyFallen, :) = 0;
            end

            % update velocity
            %Helbing equation: acceleration = (desired - current)/tau + force/mass
            accelerationX = (desiredVelocityX - agentVelocity(:,1)) ./ relaxationTime ...
                            + totalForceX / agentMass;
            accelerationY = (desiredVelocityY - agentVelocity(:,2)) ./ relaxationTime ...
                            + totalForceY / agentMass;

            agentVelocity(:,1) = agentVelocity(:,1) + accelerationX * timeperStep;
            agentVelocity(:,2) = agentVelocity(:,2) + accelerationY * timeperStep;

            %fallen agents cannot move on their own but can be pushed
            %zero out their driving-force portion (keep only force-based movement)
            agentVelocity(isFallen, :) = agentVelocity(isFallen, :) * 0.1;

            %cap speed to prevent numerical blowup
            currentSpeed = sqrt(agentVelocity(:,1).^2 + agentVelocity(:,2).^2);
            tooFast = currentSpeed > maxSpeedCap;
            if any(tooFast)
                speedScale = maxSpeedCap ./ currentSpeed(tooFast);
                agentVelocity(tooFast, 1) = agentVelocity(tooFast, 1) .* speedScale;
                agentVelocity(tooFast, 2) = agentVelocity(tooFast, 2) .* speedScale;
            end

            % update position
            position(:,1) = position(:,1) + agentVelocity(:,1) * timeperStep;
            position(:,2) = position(:,2) + agentVelocity(:,2) * timeperStep;

            % exit detection (before clamp so agents can actually leave)
            %fallen agents cannot escape (they are on the ground)
            escaped = false(N, 1);
            for exitIdx = 1:numExits
                thisExitX = exitsMatrix(exitIdx, 1);
                thisExitY = exitsMatrix(exitIdx, 2);
                thisExitW = exitsMatrix(exitIdx, 3);
                exitBottomEdge = thisExitY - thisExitW / 2;
                exitTopEdge = thisExitY + thisExitW / 2;

                if thisExitX >= Length
                    %right wall exit
                    escaped = escaped | ...
                        (~isFallen & ...
                         position(:,1) >= Length - agentRadius & ...
                         position(:,2) >= exitBottomEdge & position(:,2) <= exitTopEdge);
                else
                    %left wall exit
                    escaped = escaped | ...
                        (~isFallen & ...
                         position(:,1) <= agentRadius & ...
                         position(:,2) >= exitBottomEdge & position(:,2) <= exitTopEdge);
                end
            end

            if any(escaped)
                keep = ~escaped;
                evacuatedCount = evacuatedCount + sum(escaped);
                position = position(keep, :);
                agentVelocity = agentVelocity(keep, :);
                panicArr = panicArr(keep);
                baseSpeed = baseSpeed(keep);
                isFallen = isFallen(keep);
                N = size(position, 1);
            end

            % boundary clamp and obstacle push-out (safety net)
            if N > 0
                position(:,1) = max(agentRadius, min(position(:,1), Length - agentRadius));
                position(:,2) = max(agentRadius, min(position(:,2), Width - agentRadius));

                %push agents out of obstacles if they clipped through
                for obstacleIdx = 1:size(obstacles, 1)
                    obsXMin = obstacles(obstacleIdx,1); obsYMin = obstacles(obstacleIdx,2);
                    obsXMax = obstacles(obstacleIdx,3); obsYMax = obstacles(obstacleIdx,4);
                    insideObstacle = position(:,1) > obsXMin & position(:,1) < obsXMax & ...
                                     position(:,2) > obsYMin & position(:,2) < obsYMax;
                    for agentIdx = find(insideObstacle)'
                        distToEdges = [position(agentIdx,1)-obsXMin, obsXMax-position(agentIdx,1), ...
                                       position(agentIdx,2)-obsYMin, obsYMax-position(agentIdx,2)];
                        [~, nearestEdge] = min(distToEdges);
                        switch nearestEdge
                            case 1; position(agentIdx,1) = obsXMin - agentRadius;
                            case 2; position(agentIdx,1) = obsXMax + agentRadius;
                            case 3; position(agentIdx,2) = obsYMin - agentRadius;
                            case 4; position(agentIdx,2) = obsYMax + agentRadius;
                        end
                    end
                end
            end

            % 13. metrics
            evacHistory(step) = evacuatedCount;
            casualtyHistory(step) = casualtyCount;

            if N > 1
                currentSpeed = sqrt(agentVelocity(:,1).^2 + agentVelocity(:,2).^2);
                speedHistory(step) = mean(currentSpeed);

                %recompute cell assignments after movement
                cellOfAgent = floor(position ./ [cellDimX cellDimY]) + 1;
                cellOfAgent = max(1, min(cellOfAgent, [noGridsX noGridsY]));

                peakPressureThisStep = 0;
                peakEntropyThisStep = 0;

                for cellX = 1:noGridsX
                    for cellY = 1:noGridsY
                        agentsInThisCell = cellOfAgent(:,1) == cellX & cellOfAgent(:,2) == cellY;
                        agentCountInCell = sum(agentsInThisCell);
                        if agentCountInCell < 2
                            continue;
                        end

                        %crowd pressure = density * velocity variance
                        %best crush danger indicator from Seoul study (Liang 2024)
                        cellDensity = agentCountInCell / cellArea;
                        cellVelX = agentVelocity(agentsInThisCell, 1);
                        cellVelY = agentVelocity(agentsInThisCell, 2);
                        cellMeanVelX = mean(cellVelX);
                        cellMeanVelY = mean(cellVelY);
                        velocityVariance = mean((cellVelX - cellMeanVelX).^2 + ...
                                                (cellVelY - cellMeanVelY).^2);
                        cellPressure = cellDensity * velocityVariance;
                        if cellPressure > peakPressureThisStep
                            peakPressureThisStep = cellPressure;
                        end

                        %direction entropy (8 bins of 45 degrees each)
                        %0 = everyone same direction, 1 = total chaos
                        cellSpeed = sqrt(cellVelX.^2 + cellVelY.^2);
                        isMoving = cellSpeed > 0.01;
                        if sum(isMoving) >= 2
                            movementAngles = atan2(cellVelY(isMoving), cellVelX(isMoving));
                            angleBinEdges = -pi : (pi/4) : pi;
                            agentsPerBin = histcounts(movementAngles, angleBinEdges);
                            nonEmptyBins = agentsPerBin(agentsPerBin > 0) / sum(isMoving);
                            directionEntropy = -sum(nonEmptyBins .* log2(nonEmptyBins)) / log2(8);
                            if directionEntropy > peakEntropyThisStep
                                peakEntropyThisStep = directionEntropy;
                            end
                        end
                    end
                end

                %total body overlap across all pairs
                metricDistX = position(:,1)' - position(:,1);
                metricDistY = position(:,2)' - position(:,2);
                metricDist = sqrt(metricDistX.^2 + metricDistY.^2);
                metricDist(1:N+1:end) = inf;
                totalOverlap = sum(max(0, contactDiameter - metricDist), 'all') / 2;

                pressureHistory(step) = peakPressureThisStep;
                entropyHistory(step) = peakEntropyThisStep;
                overlapHistory(step) = totalOverlap;

            elseif N == 1
                currentSpeed = sqrt(agentVelocity(:,1).^2 + agentVelocity(:,2).^2);
                speedHistory(step) = mean(currentSpeed);
            end

        end %time steps

        %store results
        escapedFrac = evacuatedCount / max(initialTotal, 1);
        warmup = min(20, nSteps);

        resultsTable(comboIdx, :) = [...
            initialTotal, evacuatedCount, casualtyCount, ...
            mean(speedHistory(warmup:end)), ...
            max(pressureHistory), mean(entropyHistory), ...
            max(overlapHistory), escapedFrac];

        histPressure{scenario, panicLevel}   = pressureHistory;
        histEntropy{scenario, panicLevel}    = entropyHistory;
        histOverlap{scenario, panicLevel}    = overlapHistory;
        histEvacCount{scenario, panicLevel}  = evacHistory;
        histSpeed{scenario, panicLevel}      = speedHistory;
        histCasualties{scenario, panicLevel} = casualtyHistory;

        fprintf('\n--- After %d steps ---\n', nSteps);
        fprintf('Evacuated: %d / %d (%.1f%%)\n', evacuatedCount, initialTotal, 100*escapedFrac);
        fprintf('Casualties (fallen): %d\n', casualtyCount);
        fprintf('Avg speed: %.3f m/s\n', mean(speedHistory(warmup:end)));
        fprintf('Peak pressure: %.2f\n', max(pressureHistory));
        fprintf('Avg entropy: %.3f\n', mean(entropyHistory));
        fprintf('Peak overlap: %.3f m\n', max(overlapHistory));

    end
end

%% results
fprintf('\n=============== SCENARIO COMPARISON TABLE ===============\n');
fprintf('%-22s %6s %6s %6s %8s %10s %8s %10s %8s\n', ...
    'Combo', 'Total', 'Evac', 'Dead', 'AvgSpd', 'PeakPress', 'AvgEntr', 'PeakOvlap', 'Evac%');
fprintf('%s\n', repmat('-', 1, 95));
for idx = 1:comboIdx
    fprintf('%-22s %6d %6d %6d %8.3f %10.2f %8.3f %10.3f %7.1f%%\n', ...
        comboLabels{idx}, ...
        resultsTable(idx,1), resultsTable(idx,2), resultsTable(idx,3), ...
        resultsTable(idx,4), resultsTable(idx,5), resultsTable(idx,6), ...
        resultsTable(idx,7), 100*resultsTable(idx,8));
end

fprintf('\nresultsTable (raw matrix):\n');
fprintf('  columns: [totalAgents evacuated casualties avgSpeed maxPressure avgEntropy maxOverlap escapedFrac]\n');
disp(resultsTable);

function [dist, normalX, normalY, tangentX, tangentY] = agentsToSegment(agentX, agentY, segX1, segY1, segX2, segY2)
%distance from N agents to one wall segment
%agentX agentY are Nx1 vectors, segment goes from (segX1,segY1) to (segX2,segY2)
%returns distance, outward normal pointing toward agent, and wall tangent
    segDirX = segX2 - segX1;
    segDirY = segY2 - segY1;
    segLengthSq = segDirX^2 + segDirY^2;
    if segLengthSq < 1e-12
        nearestPointX = segX1 * ones(size(agentX));
        nearestPointY = segY1 * ones(size(agentX));
    else
        %how far along the segment the nearest point is (0 to 1)
        projectionT = max(0, min(1, ((agentX - segX1)*segDirX + (agentY - segY1)*segDirY) / segLengthSq));
        nearestPointX = segX1 + projectionT * segDirX;
        nearestPointY = segY1 + projectionT * segDirY;
    end
    gapX = agentX - nearestPointX;
    gapY = agentY - nearestPointY;
    dist = sqrt(gapX.^2 + gapY.^2);
    notZero = dist > 1e-12;
    normalX = zeros(size(agentX));
    normalY = zeros(size(agentX));
    normalX(notZero) = gapX(notZero) ./ dist(notZero);
    normalY(notZero) = gapY(notZero) ./ dist(notZero);
    tangentX = -normalY;
    tangentY = normalX;
end
