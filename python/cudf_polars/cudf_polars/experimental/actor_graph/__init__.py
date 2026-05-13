# SPDX-FileCopyrightText: Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES.
# SPDX-License-Identifier: Apache-2.0

"""RapidsMPF streaming-engine support."""

from __future__ import annotations

# Side-effect imports: each module registers
# ``@generate_ir_sub_network.register(...)`` handlers at import time so the
# dispatch table is populated before any query is evaluated.
import cudf_polars.experimental.actor_graph.groupby
import cudf_polars.experimental.actor_graph.io
import cudf_polars.experimental.actor_graph.join
import cudf_polars.experimental.actor_graph.repartition
import cudf_polars.experimental.actor_graph.union
import cudf_polars.experimental.collectives.shuffle
import cudf_polars.experimental.collectives.sort  # noqa: F401

__all__: list[str] = []
