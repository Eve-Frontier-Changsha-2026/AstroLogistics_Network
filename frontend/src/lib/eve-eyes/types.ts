// frontend/src/lib/eve-eyes/types.ts

export interface EveSystem {
  id: number;
  name: string;
  constellationId: number;
  regionId: number;
  location: { x: number; y: number; z: number };
  gateLinks: number[];
}

export interface EveSystemSummary {
  id: number;
  name: string;
  constellationId: number;
  regionId: number;
  location: { x: number; y: number; z: number };
}

export interface EveRoute {
  origin: EveSystem;
  destination: EveSystem;
  jumps: number;
  systems: EveSystem[];
}
