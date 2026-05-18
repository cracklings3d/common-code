# Three core contexts

CommonCode is organized as a multi-context system with Session Orchestration, Execution, and Presentation. We chose this split because cross-device continuity, host-side processing, and platform-specific UI evolve under different constraints, and keeping them separate makes ownership of Sessions, Hosts, and Presentation Profiles explicit.
