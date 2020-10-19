module S
using JSON

const CourseNum = String

struct Course
	coursenum::CourseNum
	name::String
	credit::Int
	prereqs::Vector{CourseNum}
	attributes::Vector{String}
	soft_sequence::Vector{CourseNum}
	hard_sequence::Vector{CourseNum}
end

"""An AND statement listing OR statements"""
const AttributePattern = Vector{Vector{String}}

abstract type Requirement end

struct ReqList <: Requirement
	list::Vector{CourseNum}
	jealousy::Int
	name::String
end

struct CreditDemand <: Requirement
	credit::Integer
	pattern::AttributePattern
	jealousy::Int
	name::String
end

struct Checksheet
	name::String
	requirements::Vector{Requirement}
end

const CourseRecord = Tuple{CourseNum,Int}

struct Student
	courses::Vector{CourseRecord}
	checksheets::Vector{String}
	name::String
end

struct System
	students::Vector{Student}
	courses::Vector{Course}
	checksheets::Vector{Checksheet}
end

function load_json_system(filename::String)
	system = JSON.parse(read(open(filename, "r"), String))
	System(
		load_student.(system["students"]),
		load_course.(system["courses"]),
		load_checksheet.(system["checksheets"])
	)
end

function load_student(student)
	Student(load_course_record.(student["courses"]), student["checksheets"], student["name"])
end

function load_course_record(cr)
	CourseRecord(cr)
end

function load_course(c)
	Course(c["coursenum"], c["name"], c["credit"], c["prerequisites"], c["attributes"],
		get(c, "soft sequence", []), get(c, "hard sequence", []))
end

function load_checksheet(cs)
	Checksheet(cs["name"], load_requirement.(cs["requirements"]))
end

function load_requirement(req)
	if req["type"] == "credit demand"
		CreditDemand(req["demand"], req["attribute criteria"], get(req, "jealousy", 1), req["name"])
	elseif req["type"] == "required list"
		ReqList(req["list"], get(req, "jealousy", 1), req["name"])
	else
		Exception("unrecognized requirement type")
	end
end

end
