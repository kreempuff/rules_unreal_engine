load(":rules_test.bzl", "unreal_target_test_suite")


unreal_target_test_suite(
    name = "unreal_target_test",
)

sh_binary(
    name = "Setup.sh",
    srcs = ["@unreal_engine//UnrealEngine:Setup.sh"],
    visibility = ["//visibility:public"],
)
