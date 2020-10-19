cd("../../KFSA/recc_sys")
include("recc_sys.jl")
sys = S.load_json_system("system_def.json")

function getfrom(dicts::Vector{}, key::Symbol, val)
	for d in dicts
		if getproperty(d, key) == val
			return d
		end
	end
end


function fit_classes(
		taken_courses::Vector{S.CourseRecord},
		course_info::Vector{S.Course},
		checksheet::Main.S.Checksheet)
	#=

	this function will find the best assignment of courses to requirements
	we need only two types of requirements in order to encode every major
	(I think, I didn't really bother with the art and education schools)
	The two types of requirement: A list of required courses
	A credit requirement of classes that fulfill a set of conditions \

	these requirements have three levels of specificity.
	A course that matches with the reqlist requirement must be assigned to that requirement
	A coourse that matches a conditional credit demand should probably be assigned to that requirement
	A course that matches an unconditional credit demand (free electives) probably should not be assigned
	to that requirement.

	The reqlist requirements should never overlap on the same checksheet. If
	there is more than one free elective requirement, it doesn't matter what
	course gets assigned to what requirement. However, if there is a set of
	conditional credit demands, and a course could be used to fulfill either
	requirement, there is no way to determine if it is better assigned to one or
	the other, without considering the system as a whole. We therefore need to
	have a recursive middle-specificity-allocation function.
	=#

	#Step 1: determine high-specificity assignments
	hs_reqs, ls_reqs = high_specificity_reqs(checksheet.requirements)

	#we need a record to know what requirement each course is going to
	taken_course_record = [(course[1], "") for course in taken_courses]

	#we also need to know how many credit-hours of requirements are fulfilled
	#per req
	hs_req_fulfilled = zeros(length(hs_reqs))

	#every course is unique so we don't need any duplicate guards
	for i in 1:length(taken_course_record)
		for j in 1:length(hs_reqs)
			for req_course_num in hs_reqs[j].list
				if req_course_num == taken_course_record[i][1]
					taken_course_record[i] = (taken_course_record[i][1], hs_reqs[j].name)
					credits = getfrom(course_info, :coursenum, req_course_num).credit
					hs_req_fulfilled[j] += credits
				end end end end

	#Step 2: determine medium-specificity assignments
	ms_reqs, ls_reqs = med_specificity_reqs(ls_reqs)

	#assign courses that fulfill only one medium-specific requirement to that
	#req, while earmarking requirements that fulfill more than one requirement.
	nondeterminant_courses = []

	#now that we are dealing with credit demands instead of required course
	#lists, we need to keep track of when credit demands are fulfilled
	demanded_credits = [req.credit for req in ms_reqs]
	changed_value = true

	#as requirements become satisfied, it is possible that previously
	#nondeterminant courses will become assignable
	#every time something changes, we need to recheck everything
	while changed_value
		changed_value = false
		nondeterminant_courses = []
		for i in 1:length(taken_course_record)
			if !(taken_course_record[i][2] == "")
				continue
			end
			course = getfrom(course_info, :coursenum, taken_course_record[i][1])
			possible_assignment_indexes = []
			for j in 1:length(ms_reqs)
				if demanded_credits[j] <= 0
					continue
				end
				if attribute_pattern_check(course.attributes, ms_reqs[j].pattern)
					push!(possible_assignment_indexes, j)
				end
			end
			if length(possible_assignment_indexes) == 1
				#there is only one match so it's always a good idea to put this here
				requirement_name = ms_reqs[possible_assignment_indexes[1]].name
				taken_course_record[i] = (taken_course_record[i][1], requirement_name)
				demanded_credits[possible_assignment_indexes[1]] -= course.credit
				changed_value = true
			elseif length(possible_assignment_indexes) == 0
				#this course fulfills none of the credit demands' criteria
				continue
			else
				#there is more than one requirement this course could be used for
				#we will save the index of this course
				push!(nondeterminant_courses, [i, possible_assignment_indexes])
			end
		end
	end

	#do the recursive try-every-option thing
	taken_course_record, demanded_credits, new_nondeterminant_courses = decide_nondeterminants(
			nondeterminant_courses, taken_course_record, demanded_credits,
			ms_reqs, course_info)

	#step 3: trivially allocate remaining courses to free elective reqs
	for j in 1:length(ls_reqs)
		for req_course_num in ls_reqs[j].list
			for i in 1:length(taken_course_record)
				if (taken_course_record[i][2] == "")
					taken_course_record[i] = (taken_course_record[i][1], ls_reqs[j].name)
					credits = getfrom(course_info, :coursenum, req_course_num).credit
					ls_req_fulfilled[j] += credits
				end end end end

	taken_course_record, nondeterminant_courses, new_nondeterminant_courses
end

function high_specificity_reqs(reqs::Vector{S.Requirement})
	high_spec = Vector{S.Requirement}()
	low_spec = Vector{S.Requirement}()
	for req in reqs
		push!(isa(req, S.ReqList) ? high_spec : low_spec, req)
	end
	high_spec, low_spec
end

function med_specificity_reqs(reqs::Vector{S.Requirement})
	#=A medium specificity requirement is one that has conditional tags=#
	med_spec = Vector{S.Requirement}()
	low_spec = Vector{S.Requirement}()
	for req in reqs
		push!(length(req.pattern) > 0 ? med_spec : low_spec, req)
	end
	med_spec, low_spec
end

function attribute_pattern_check(attributes, pattern)::Bool
	all([any([(att in attributes) for att in pattern_part]) for pattern_part in pattern])
end

function decide_nondeterminants(nondeterminants, taken_course_record,
		demanded_credits, ms_reqs, course_info)
	if length(nondeterminants) == 0 || sum(demanded_credits) == 0
		#we have found an assignment that fulfills all the requirements, or we
		#have run out of courses to assign
		return taken_course_record, demanded_credits, nondeterminants
	end
	remaining_nondet = nondeterminants[1:end-1]
	current_nondet = nondeterminants[end]
	current_course = getfrom(course_info, :coursenum,
			taken_course_record[current_nondet[1]][1])
	best_found_remaining_demand = sum(demanded_credits)
	best_found_assignment = nothing
	selected_requirement = 0
	for requirement_index in current_nondet[2]
		#if the requirement referred to has already been satisfied, skip it
		if demanded_credits[requirement_index] <= 0 continue end

		#if this is the requirement this nondeterminant course was assigned
		#to, how efficiently would the remaining courses be assigned?
		demanded_credits[requirement_index] -= current_course.credit
		trial_assignment, trial_demanded_credits, remaining_nondet =
				decide_nondeterminants(remaining_nondet, taken_course_record,
				demanded_credits, ms_reqs, course_info)
		#but we don't know if we're going to use this solution or not, so put
		#the demanded_credits record back how it was
		demanded_credits[requirement_index] += current_course.credit

		#how many credit-hours are still an unfulfilled requirement?
		if sum(trial_demanded_credits) <= best_found_remaining_demand
			#if we have found a good solution, save it
			best_found_remaining_demand = sum(trial_demanded_credits)
			best_found_assignment = trial_assignment
			selected_requirement = requirement_index
		end
	end
	#if a requirement was found for this course to be assigned to, update the
	#records
	if selected_requirement > 0
		#now, selected_requirement contains the one of the best possible
		#requirements to assign this course to. Update the record and
		#demanded_credits to reflect this, and return
		requirement_name = ms_reqs[selected_requirement].name
		taken_course_record[current_nondet[1]] = (taken_course_record[current_nondet[1]][1], requirement_name)
		demanded_credits[selected_requirement] -= current_course.credit
	end
	taken_course_record, demanded_credits, remaining_nondet
end

student = getfrom(sys.students, :name, "Zoop DeScwe")
first_checksheet = getfrom(sys.checksheets, :name, student.checksheets[1])
fit_classes(student.courses, sys.courses, first_checksheet)
