# Copyright 1999-2012 Gentoo Foundation
# Copyright 2010 Sebastien Fabbro
# Copyright 2008, 2009 Bo Ørsted Andresen
# Copyright 2008, 2009 Mike Kelly
# Copyright 2009 David Leverton
# Distributed under the terms of the GNU General Public License v2

# If your package provides pkg_postinst or pkg_prerm phases, you need to be
# sure you explicitly run alternatives_pkg_{postinst,prerm} where appropriate.

ALTERNATIVES_DIR="/etc/env.d/alternatives"

DEPEND=">=app-admin/eselect-1.3.3-r100"
RDEPEND="${DEPEND}
	!app-admin/eselect-blas
	!app-admin/eselect-cblas
	!app-admin/eselect-lapack"

# alternatives_for alternative provider importance source target [ source target [...]]
alternatives_for() {
	#echo alternatives_for "${@}"

	(( $# >= 5 )) && (( ($#-3)%2 == 0)) || die "${FUNCNAME} requires exactly 3+N*2 arguments where N>=1"
	local x dupl alternative=${1} provider=${2} importance=${3} index unique src target ret=0
	shift 3

	# make sure importance is a signed integer
	if [[ -n ${importance} ]] && ! [[ ${importance} =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
		eerror "Invalid importance (${importance}) detected"
		((ret++))
	fi

	[[ -d "${ED}${ALTERNATIVES_DIR}/${alternative}/${provider}" ]] || dodir "${ALTERNATIVES_DIR}/${alternative}/${provider}"

	# keep track of provided alternatives for use in pkg_{postinst,prerm}. keep a mapping between importance and
	# provided alternatives and make sure the former is set to only one value
	if ! has "${alternative}:${provider}" "${ALTERNATIVES_PROVIDED[@]}"; then
		index=${#ALTERNATIVES_PROVIDED[@]}
		ALTERNATIVES_PROVIDED+=( "${alternative}:${provider}" )
		ALTERNATIVES_IMPORTANCE[index]=${importance}
		[[ -n ${importance} ]] && echo "${importance}" > "${ED}${ALTERNATIVES_DIR}/${alternative}/${provider}/_importance"
	else
		for((index=0;index<${#ALTERNATIVES_PROVIDED[@]};index++)); do
			if [[ ${alternative}:${provider} == ${ALTERNATIVES_PROVIDED[index]} ]]; then
				if [[ -n ${ALTERNATIVES_IMPORTANCE[index]} ]]; then
					if [[ -n ${importance} && ${ALTERNATIVES_IMPORTANCE[index]} != ${importance} ]]; then
						eerror "Differing importance (${ALTERNATIVES_IMPORTANCE[index]} != ${importance}) detected"
						((ret++))
					fi
				else
					ALTERNATIVES_IMPORTANCE[index]=${importance}
					[[ -n ${importance} ]] && echo "${importance}" > "${ED}${ALTERNATIVES_DIR}/${alternative}/${provider}/_importance"
				fi
			fi
		done
	fi

	while (( $# >= 2 )); do
		src=${1//+(\/)/\/}; target=${2//+(\/)/\/}
		if [[ ${src} != /* ]]; then
			eerror "Source path must be absolute, but got ${src}"
			((ret++))

		else
			local reltarget= dir=${ALTERNATIVES_DIR}/${alternative}/${provider}${src%/*}
			while [[ -n ${dir} ]]; do
				reltarget+=../
				dir=${dir%/*}
			done

			reltarget=${reltarget%/}
			[[ ${target} == /* ]] || reltarget+=${src%/*}/
			reltarget+=${target}
			dodir "${ALTERNATIVES_DIR}/${alternative}/${provider}${src%/*}"
			dosym "${reltarget}" "${ALTERNATIVES_DIR}/${alternative}/${provider}${src}"

			# say ${ED}/sbin/init exists and links to /bin/systemd (which doesn't exist yet)
			# the -e test will fail, so check for -L also
			if [[ -e ${ED}${src} || -L ${ED}${src} ]]; then
				local fulltarget=${target}
				[[ ${fulltarget} != /* ]] && fulltarget=${src%/*}/${fulltarget}
				if [[ -e ${ED}${fulltarget} || -L ${ED}${fulltarget} ]]; then
					die "${src} defined as provider for ${fulltarget}, but both already exist in \${ED}"
				else
					mv "${ED}${src}" "${ED}${fulltarget}" || die
				fi
			fi
		fi
		shift 2
	done

	[[ ${ret} -eq 0 ]] || die "Errors detected for ${provider}, provided for ${alternative}"
}

cleanup_old_alternatives_module() {
	local alt=${1} old_module="${EROOT}/usr/share/eselect/modules/${alt}.eselect"
	if [[ -f "${old_module}" && "$(source "${old_module}" &>/dev/null; echo "${ALTERNATIVE}")" == "${alt}" ]]; then
		local version="$(source "${old_module}" &>/dev/null; echo "${VERSION}")"
		if [[ "${version}" == "0.1" || "${version}" == "20080924" ]]; then
			echo rm "${old_module}"
			rm "${old_module}" || eerror "rm ${old_module} failed"
		fi
	fi
}

alternatives-2_pkg_postinst() {
	local a alt provider module_version="20090908"
	for a in "${ALTERNATIVES_PROVIDED[@]}"; do
		alt="${a%:*}"
		provider="${a#*:}"
		if [[ ! -f "${EROOT}/usr/share/eselect/modules/auto/${alt}.eselect" \
			|| "$(source "${EROOT}/usr/share/eselect/modules/auto/${alt}.eselect" &>/dev/null; echo "${VERSION}")" \
				-ne "${module_version}" ]]; then
			#einfo "Creating alternatives module for ${alt}"
			if [[ ! -d ${EROOT}/usr/share/eselect/modules/auto ]]; then
				install -d "${EROOT}"/usr/share/eselect/modules/auto || eerror "Could not create eselect modules dir"
			fi
			cat > "${EROOT}/usr/share/eselect/modules/auto/${alt}.eselect" <<-EOF
				# This module was automatically generated by alternatives.eclass
				DESCRIPTION="Alternatives for ${alt}"
				VERSION="${module_version}"
				MAINTAINER="eselect@gentoo.org"
				ESELECT_MODULE_GROUP="Alternatives"

				ALTERNATIVE="${alt}"

				inherit alternatives
			EOF
		fi

		#echo eselect "${alt}" update "${provider}"
		einfo "Creating ${provider} alternative module for ${alt}"
		eselect "${alt}" update "${provider}"

		cleanup_old_alternatives_module ${alt}
	done
}

alternatives-2_pkg_prerm() {
	local a alt provider p ignore
	[[ -n ${REPLACED_BY_ID} ]] || ignore=" --ignore"
	for a in "${ALTERNATIVES_PROVIDED[@]}"; do
		alt="${a%:*}"
		provider="${a#*:}"
		#echo "Making sure ${alt} has a valid provider"
		#echo eselect "${alt}" update${ignore} "${provider}"
		eselect "${alt}" update${ignore} "${provider}" && continue
		einfo "Removed ${provider} alternative module for ${alt}, current is $(eselect ${alt} show)"
		if [[ $? -eq 2 ]]; then
			einfo "Cleaning up unused alternatives module for ${alt}"
			echo rm "${EROOT}/usr/share/eselect/modules/auto/${alt}.eselect"
			rm "${EROOT}/usr/share/eselect/modules/auto/${alt}.eselect" ||
				eerror rm "${EROOT}/usr/share/eselect/modules/auto/${alt}.eselect" failed
		fi
	done
}

EXPORT_FUNCTIONS pkg_postinst pkg_prerm
