/**
 * Copyright 2025 Circle Internet Group, Inc. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
pragma solidity ^0.8.29;

/// @title BatchedDelta
///
/// @notice Describes a single balance change for a single address as part of a batch.
/// @dev This changes around balances, so the entire batch must be validated to add to zero.
///      We use normal ABI encoding for this instead of the TypedMemView for many of the other
///      structures as it doesn't need to be used cross-chain and this is significant more
///      efficient.
struct BatchedDelta {
    address depositor; // The address in question
    int256 value; //      Positive means they're getting money, negative means deducted
}
