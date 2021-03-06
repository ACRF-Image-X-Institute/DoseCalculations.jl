#=
    External surfaces

This file contains stuctures for computing source-surface distances (SSDs) from
external surfaces. External surfaces are structures which encompasses all dose
points, and are hence used to compute the depth of the dose point within the
surface.

It current contains two types of external surfaces:

 - ConstantSurface: Returns a constant SSD regardless of position of the dose
                    point or orientation of the treatment beam.

 - PlaneSurface: Returns the distance from the source to a plane, but does not
                 account for the orientation of the treatment beam.
=#
using LinearAlgebra, Meshes

export ConstantSurface, PlaneSurface, MeshSurface, IsoplaneSurface
export getdepth, getSSD, compute_SSD!

#--- AbstractExternalSurface --------------------------------------------------
"""
    AbstractExternalSurface

Supertype for external surfaces.
"""
abstract type AbstractExternalSurface end

"""
    getSSD(surf::AbstractExternalSurface, pᵢ)

Get the Source-Surface Distance (SSD) between for the given position `pᵢ`.

The position `pᵢ` is in the IEC Beam Limiting Device (BLD) coordinate system
(whose center is at the radiation source).
"""
getSSD(surf::AbstractExternalSurface, pᵢ)

"""
    getdepth(surf::AbstractExternalSurface, pᵢ)

Get the depth of the position `pᵢ` below the surface `surf`.
"""
function getdepth(surf::AbstractExternalSurface, pᵢ::T) where T<:Union{AbstractVector, Point3}
    norm(pᵢ - T(0, 0, 0)) .- getSSD(surf, pᵢ)
end


#--- ConstantSurface ----------------------------------------------------------

"""
    ConstantSurface

An external surface with a constant source surface distance, regardless of the
position. This surface is largely used for testing purposes as its inherently
unphysical.
"""
struct ConstantSurface{T} <: AbstractExternalSurface
    source_surface_distance::T
end

"""
    getSSD(calc::ConstantSurface, pᵢ)

When applied to a `ConstantSurface`, it returns a constant SSD value, regardless
of position `pᵢ`.
"""
getSSD(surf::ConstantSurface, pᵢ) = surf.source_surface_distance


#--- PlaneSurface -------------------------------------------------------------

"""
    PlaneSurface

A planar external surface at a constant distance from the source.
"""
struct PlaneSurface{T} <: AbstractExternalSurface
    source_surface_distance::T
end

"""
    getSSD(surf::PlaneSurface, pᵢ)

When applied to a `PlaneSurface`, it returns the distance to the plane.

It assumes the plane is at position (0, 0, surf.source_surface_distance) with
normal pointing towards the source
"""
function getSSD(surf::PlaneSurface, pᵢ)
    x, y, z = pᵢ
    α² = (surf.source_surface_distance/z)^2
    √(α²*(x^2 + y^2) + surf.source_surface_distance^2)
end

getSSD(surf::PlaneSurface, pᵢ::Point) = getSSD(surf, coordinates(pᵢ))

#--- MeshSurface --------------------------------------------------------------

"""
    MeshSurface

An external surface defined by a 3D mesh.
"""
struct MeshSurface{T} <: AbstractExternalSurface
    mesh::Mesh{3, T}
end

"""
    getSSD(surf::MeshSurface, pᵢ)

When applied to a `MeshSurface`, it returns the smallest distance to the mesh.
"""
function getSSD(surf::MeshSurface, pᵢ::T) where T<:AbstractVector
    pₛ = Point(0, 0, 0)
    line = Ray(pₛ, pᵢ)
    pI = intersect_mesh(line, surf.mesh)
    if(length(pI)==0)
        return nothing
    end
    minimum(norm.(pI .- Ref(pₛ)))
end

#--- IsoplaneSurface --------------------------------------------------------------

"""
    IsoplaneSurface

An external surface collapsed onto the iso-plane.

Can be precomputed for given gantry angles, avoiding costly mesh-segment
intersections.
"""
struct IsoplaneSurface{T<:AbstractFloat, TMatrix<:AbstractMatrix} <: AbstractExternalSurface
    grid::GridUniform2D{T}
    source_surface_distance::TMatrix
    source_axis_distance::T
end

"""
    IsoplaneSurface(xg, yg, SAD)

Construct a `IsoplaneSurface` out of two axes and the Source-Axis Distance (SAD). 
"""
function IsoplaneSurface(xg::AbstractVector{T}, yg::AbstractVector{T}, SAD::T) where T<:AbstractFloat
    grid = GridUniform2D(xg, yg)
    ssd = Matrix{Union{T, Nothing}}(undef, size(grid)) #= Needs both T and Nothing, as sometimes
                                                          there are no intersections =#
    IsoplaneSurface(grid, ssd, SAD)
end

"""
    IsoplaneSurface(xg, yg, SAD)

Construct a `IsoplaneSurface` out of two axes and the Source-Axis Distance (SAD). 
"""
function IsoplaneSurface(pos::AbstractVector, Δx, Δy, SAD::T) where T<:AbstractFloat

    xmin, ymin = scale_to_isoplane(pos[1], -SAD)
    xmax, ymax = xmin, ymin

    for i in eachindex(pos)
        x′, y′ = scale_to_isoplane(pos[i], -SAD)
        xmin, xmax = min(xmin, x′), max(xmax, x′)
        ymin, ymax = min(ymin, y′), max(ymax, y′)
    end

    xg = snapped_range(xmin, xmax, Δx)
    yg = snapped_range(ymin, ymax, Δy)
    grid = GridUniform2D(xg, yg)
    ssd = Matrix{Union{T, Nothing}}(undef, size(grid)) #= Needs both T and Nothing, as sometimes
                                                          there are no intersections =#
    IsoplaneSurface(grid, ssd, SAD)
end

"""
    compute_SSD!(surf::IsoplaneSurface, mesh_surface::MeshSurface)

Compute the SSD matrix from the 3D mesh stored in `MeshSurface`.
"""
function compute_SSD!(surf::IsoplaneSurface, mesh_surf::MeshSurface)
    Δx, Δy = DoseCalculations.spacing(surf.grid)
    surf.source_surface_distance .= getSSD.(Ref(mesh_surf),
                                            Vec.(getindex.(surf.grid, 1),
                                                 getindex.(surf.grid, 2),
                                                 -surf.source_axis_distance))
end

compute_SSD!(surf::IsoplaneSurface, mesh::Mesh) = compute_SSD!(surf, MeshSurface(mesh))

"""
    getSSD(surf::IsoplaneSurface, pᵢ)

When applied to a `IsoplaneSurface`, it locates the position on the isoplane
then returns the source-surface distance.

Must call `compute_SSD!` on `surf` first.
"""
function getSSD(surf::IsoplaneSurface, pᵢ::AbstractVector)
    x′, y′ = scale_to_isoplane(pᵢ, -surf.source_axis_distance)
    interp(surf.grid, surf.source_surface_distance, x′, y′)
end

getSSD(surf::IsoplaneSurface, pᵢ::Point) = getSSD(surf, coordinates(pᵢ))
