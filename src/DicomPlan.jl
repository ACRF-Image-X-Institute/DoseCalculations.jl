#
#   DICOM Plan
#
# Functions for loading in DICOM Plan data. Currently only tested on VMAT SPARK
# data.
#

using DICOM
export load_dicom

#--- DICOM IO ----------------------------------------------------------------------------------------------------------

"""
    load_dicom(filename)

Load a DICOM RP file into a Vector{TreatmentField}.
"""
function load_dicom(filename)
    dcm = dcm_parse(filename)

    referenced_dose = load_ref_dose.(dcm[tag"FractionGroupSequence"][1].ReferencedBeamSequence)
    load_beam.(dcm[tag"BeamSequence"], referenced_dose)
end

"""
    load_beam(beam, total_meterset)

Load a beam from a control point sequence in a DICOM RP file.
"""
function load_beam(beam, total_meterset)

    SAD = beam[tag"SourceAxisDistance"]

    controlpoints = beam[tag"ControlPointSequence"]

    controlpoint = controlpoints[1]

    # 
    ncontrol = beam[tag"NumberOfControlPoints"]
    θb = deg2rad(controlpoint[tag"BeamLimitingDeviceAngle"])
    Ḋ = controlpoint[tag"DoseRateSet"]/60. # Convert from MU/min to MU/s

    isocenter = SVector(controlpoint[tag"IsocenterPosition"]...)

    # Jaws
    jaws_x = controlpoint[tag"BeamLimitingDevicePositionSequence"][1][tag"LeafJawPositions"]
    jaws_y = controlpoint[tag"BeamLimitingDevicePositionSequence"][2][tag"LeafJawPositions"]
    jaws = Jaws(jaws_x, jaws_y)

    mlc_boundaries = beam[tag"BeamLimitingDeviceSequence"][3]["LeafPositionBoundaries"]
    mlc = MultiLeafCollimator(mlc_boundaries)
    nleaves = length(mlc)

    ϕg = zeros(ncontrol)
    mlcx = zeros(2, length(mlc), ncontrol)
    meterset = zeros(ncontrol)

    for (i, controlpoint) in enumerate(controlpoints)
        ϕg[i] = deg2rad(controlpoint[tag"GantryAngle"])
        if(ϕg[i] > π)
            ϕg[i] -= 2π
        end
        mlcx[:,:,i] .= reshape(controlpoint[tag"BeamLimitingDevicePositionSequence"][end][tag"LeafJawPositions"],
                               nleaves, 2)'

        meterset[i] = total_meterset*controlpoint[tag"CumulativeMetersetWeight"]
    end

    VMATField(ncontrol, mlcx, mlc, jaws, θb, ϕg, meterset, :cumulative, Ḋ, isocenter, SAD)
end

"""
    load_ref_dose(beam)

Load a reference dose, used for calculating the meterset in a control point
sequence
"""
load_ref_dose(beam) = beam[tag"BeamMeterset"]
