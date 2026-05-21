/**
 * @param first
 * @param last
 * @return {String}
 * @properties={typeid:24,uuid:"49E30F4C-05ED-4A45-9149-3DB2E1172708"}
 */
function formatName(first, last) {
	let _sFullName = `${first} ${last}`;
	
	return utils.stringInitCap(_sFullName);
}