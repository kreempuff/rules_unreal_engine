load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load(":rules.bzl", "unreal_target")

# ==== Check actions ====

def _inspect_actions_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    actions = analysistest.target_actions(env)
    asserts.equals(env, 1, len(actions))
    action_output = actions[0].outputs.to_list()[0]

    # If preferred, could pass these values as "expected" and "actual" keyword
    # arguments.
    asserts.equals(env, target_under_test.label.name + ".Target.cs", action_output.basename)

    # If you forget to return end(), you will get an error about an analysis
    # test needing to return an instance of AnalysisTestResultInfo.
    return analysistest.end(env)

# Create the testing rule to wrap the test logic. This must be bound to a global
# variable, not called in a macro's body, since macros get evaluated at loading
# time but the rule gets evaluated later, at analysis time. Since this is a test
# rule, its name must end with "_test".
inspect_actions_test = analysistest.make(_inspect_actions_test_impl)

# Macro to setup the test.
def _test_inspect_actions():
    # Rule under test. Be sure to tag 'manual', as this target should not be
    # built using `:all` except as a dependency of the test.
    unreal_target(name = "inspect_actions_subject", tags = ["manual"], type = "game")

    # Testing rule.
    inspect_actions_test(
        name = "inspect_actions_test",
        target_under_test = ":inspect_actions_subject",
    )
    # Note the target_under_test attribute is how the test rule depends on
    # the real rule target.

# Entry point from the BUILD file; macro for running each test case's macro and
# declaring a test suite that wraps them together.
def unreal_target_test_suite(name):
    # Call all test functions and wrap their targets in a suite.
    _test_inspect_actions()
    # ...

    native.test_suite(
        name = name,
        tests = [
            ":inspect_actions_test",
            # ...
        ],
    )
