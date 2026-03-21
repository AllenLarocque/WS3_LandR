Overall Goal: connect the landR set of SpaDES modules to the WS3 wood supply model.
- LandR should handle most things
- SpaDES should be able to bring in modules to deal with other processes (i.e. fire)
- WS3 should deal with harvesting by ingesting inventory and growth curves and outputting and performing harvesting schedules.
- To do this we will need to use LandR to create growth curves matching our inventory. We'll adopt biomass_yieldTables to do this. We might need to do some work on this.


Resources:
Please refer to the ai helper repos:
SpaDES: https://github.com/AllenLarocque/spades.ai
WS3: https://github.com/AllenLarocque/ws3.ai

Repo for WS3: https://github.com/UBC-FRESH/ws3
Documentation for WS3: https://ws3.readthedocs.io/en/dev/

Also refer to the github repos :
Use Biomass_borealDataPrep to prepare inventory, and to parameterize the LandR model:
- https://github.com/PredictiveEcology/Biomass_borealDataPrep
Use Biomass_core to simulate growth
- https://github.com/PredictiveEcology/Biomass_core
Use Biomass_yieldTables to generate growth curves to feed into WS3
- https://github.com/DominiqueCaron/Biomass_yieldTables


Approach:
I would like you to build a global.R and run it from the terminal using the 'source' function. Use this to iterate and ask me if there are errors or you require human input.

Outline:
LandR should define the study area
LandR should define ecolocations
LandR should provide initial inventory, as well as inventory for each WS3 planning event.

At first ecolocations should correspond to the WS3 development types. Then please add a simple netdown process to harvest only harvestable areas, similar to what was used in simpleHarvest here:
- https://github.com/pkalanta/simpleHarvest/tree/parvintesting#

We need to define growth curves for WS3, one per development type.
- To do this, I want to simulate growth curves similar to Biomass_yieldTables. 
- Ask me for more feedback please.

Notes:
Do NOT use WS3's implementation of carbon outputs and linkage with CBM. We will rely on SpaDES LandRCBM for that.
