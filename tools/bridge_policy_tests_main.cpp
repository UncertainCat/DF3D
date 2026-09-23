// bridge_policy_tests: every header-only bridge / extension policy test in
// one doctest binary. The client mailbox test relaunches this executable as
// a producer child (argv[1] = region name), which bypasses doctest.
#define DOCTEST_CONFIG_IMPLEMENT
#include "doctest.h"
#include <cstring>

int clientMailboxChild(int argc, char** argv);

int main(int argc, char** argv) {
    if (argc > 1 && std::strncmp(argv[1], "Local\\df3d_multiclient_test_", 28) == 0)
        return clientMailboxChild(argc, argv);
    return doctest::Context(argc, argv).run();
}
