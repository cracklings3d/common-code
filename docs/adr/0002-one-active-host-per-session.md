# One active host per session

Each Session binds to one active Host at a time, and attached Clients act as reconnectable control surfaces rather than taking over execution when the User changes devices. We chose this because it matches the leave-the-PC / continue-on-phone workflow while avoiding first-version complexity around host migration and multi-host coordination.
