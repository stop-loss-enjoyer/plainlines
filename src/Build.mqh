// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// Build mode. ./build.sh rewrites this file in its temporary build root only, never here:
//   ./build.sh            (nothing defined) demo build: trades only on a demo account -> build/PlainlinesDemo.ex5
//   ./build.sh --dev      #define PL_DEV_LOG: dev.log and the command channel, demo only -> build/PlainlinesDev.ex5
//   ./build.sh --release  #define PL_RELEASE: trades on any account -> build/Plainlines.ex5
// Nothing is defined in the repository copy; audit.sh refuses PL_DEV_LOG and PL_RELEASE anywhere in src.
