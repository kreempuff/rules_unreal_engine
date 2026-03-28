"""Unreal Engine build configuration settings.

Defines config_settings for the two main configuration axes:
1. Target type: game, editor, server, client, program
2. Build configuration: debug, development, test, shipping

Usage in .bazelrc:
    # Game client, development build (default)
    build --//bzl:target_type=game --//bzl:build_config=development

    # Editor build
    build:editor --//bzl:target_type=editor --//bzl:build_config=development

    # Shipping game
    build:shipping --//bzl:target_type=game --//bzl:build_config=shipping

    # Dedicated server
    build:server --//bzl:target_type=server --//bzl:build_config=development
"""

# These are the defines that change based on target type
def ue_target_type_defines():
    """Returns defines based on target type (game/editor/server/client/program)."""
    return select({
        "@rules_unreal_engine//bzl:target_type_editor": [
            "WITH_EDITOR=1",
            "WITH_EDITORONLY_DATA=1",
            "WITH_UNREAL_DEVELOPER_TOOLS=1",
            "UE_GAME=0",
            "UE_SERVER=0",
            "IS_PROGRAM=0",
        ],
        "@rules_unreal_engine//bzl:target_type_server": [
            "WITH_EDITOR=0",
            "WITH_EDITORONLY_DATA=0",
            "WITH_UNREAL_DEVELOPER_TOOLS=0",
            "UE_GAME=0",
            "UE_SERVER=1",
            "IS_PROGRAM=0",
        ],
        "@rules_unreal_engine//bzl:target_type_program": [
            "WITH_EDITOR=0",
            "WITH_EDITORONLY_DATA=0",
            "WITH_UNREAL_DEVELOPER_TOOLS=0",
            "UE_GAME=0",
            "UE_SERVER=0",
            "IS_PROGRAM=1",
        ],
        # Default: game
        "//conditions:default": [
            "WITH_EDITOR=0",
            "WITH_EDITORONLY_DATA=0",
            "WITH_UNREAL_DEVELOPER_TOOLS=0",
            "UE_GAME=1",
            "UE_SERVER=0",
            "IS_PROGRAM=0",
        ],
    })

# These are the defines that change based on build configuration
def ue_build_config_defines():
    """Returns defines based on build configuration (debug/development/test/shipping)."""
    return select({
        "@rules_unreal_engine//bzl:build_config_debug": [
            "UE_BUILD_DEBUG=1",
            "UE_BUILD_DEVELOPMENT=0",
            "UE_BUILD_TEST=0",
            "UE_BUILD_SHIPPING=0",
        ],
        "@rules_unreal_engine//bzl:build_config_test": [
            "UE_BUILD_DEBUG=0",
            "UE_BUILD_DEVELOPMENT=0",
            "UE_BUILD_TEST=1",
            "UE_BUILD_SHIPPING=0",
        ],
        "@rules_unreal_engine//bzl:build_config_shipping": [
            "UE_BUILD_DEBUG=0",
            "UE_BUILD_DEVELOPMENT=0",
            "UE_BUILD_TEST=0",
            "UE_BUILD_SHIPPING=1",
        ],
        # Default: development
        "//conditions:default": [
            "UE_BUILD_DEBUG=0",
            "UE_BUILD_DEVELOPMENT=1",
            "UE_BUILD_TEST=0",
            "UE_BUILD_SHIPPING=0",
        ],
    })

# Defines that are always the same regardless of configuration
UE_CONSTANT_DEFINES = [
    "__UNREAL__=1",
    "WITH_ENGINE=1",
    "WITH_PLUGIN_SUPPORT=1",
    "WITH_SERVER_CODE=1",
    "WITH_VERSE_VM=0",
    "WITH_VERSE_COMPILER=0",
    "IS_MONOLITHIC=0",
    "TBBMALLOC_ENABLED=0",
    "USE_MALLOC_BINNED2=1",
    "USE_MALLOC_BINNED3=0",
    "USE_STATS_WITHOUT_ENGINE=0",
    "FORCE_USE_STATS=0",
    'UBT_MODULE_MANIFEST="Manifest.dat"',
    'UBT_MODULE_MANIFEST_DEBUGGAME="Manifest-DebugGame.dat"',
    'UE_APP_NAME="UnrealGame"',
]
