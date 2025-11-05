// Copyright Test

#pragma once

#include "CoreMinimal.h"
#include "TestEnum.generated.h"

/**
 * Test enum for UHT code generation
 */
UENUM(BlueprintType)
enum class ETestEnum : uint8
{
	Value1 UMETA(DisplayName="First Value"),
	Value2 UMETA(DisplayName="Second Value"),
	Value3 UMETA(DisplayName="Third Value"),
};
