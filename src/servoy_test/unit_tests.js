/**
 * @properties={typeid:24,uuid:"5CDF529A-3A2E-4E04-8211-AEA7330F23A6"}
 */
function test_formatName_returnsFullName() {
     // arrange
     var first = 'Ada';
     var last = 'Lovelace';
 
     // act
     var result = scopes.myUtils.formatName(first, last);
 
     // assert
     jsunit.assertEquals('Ada Lovelace', result);
 }