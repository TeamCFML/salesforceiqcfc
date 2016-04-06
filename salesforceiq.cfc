/*
  Copyright (c) 2016, Matthew Clemente, John Berquist

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
*/
component output="false" displayname="SalesforceIQ.cfc"  {

  variables.utcBaseDate = dateAdd( "l", createDate( 1970,1,1 ).getTime() * -1, createDate( 1970,1,1 ) );
  variables.integerFields = [ "_start", "_limit" ];
  variables.numericFields = [  ];
  variables.timestampFields = [ "_modifiedDate", "modifiedDate" ];
  variables.booleanFields = [  ];
  variables.arrayFields = [ "_ids" ];
  variables.fileFields = [  ];
  variables.dictionaryFields = {
    o = { required = [ ], optional = [  ] }
  };

  public any function init( required string apiKey, required string apiSecret, string baseUrl = "https://api.salesforceiq.com/v2", numeric httpTimeout = 60, boolean includeRaw = true ) {

    structAppend( variables, arguments );
    return this;
  }

  public struct function listAccounts( array _ids, numeric _start = "0", numeric _limit = "50", string _modifiedDate   ) {

    return apiCall( "/accounts", setupParams( arguments ), "get" );
  }


  // PRIVATE FUNCTIONS
  private struct function apiCall( required string path, array params = [ ], string method = "get" )  {

    var fullApiPath = variables.baseUrl & path;
    var requestStart = getTickCount();


    var apiResponse = makeHttpRequest( urlPath = fullApiPath, params = params, method = method );

    var result = { "api_request_time" = getTickCount() - requestStart, "status_code" = listFirst( apiResponse.statuscode, " " ), "status_text" = listRest( apiResponse.statuscode, " " ) };
    if ( variables.includeRaw ) {
      result[ "raw" ] = { "method" = ucase( method ), "path" = fullApiPath, "params" = serializeJSON( params ), "response" = apiResponse.fileContent };
    }
    structAppend(  result, deserializeJSON( apiResponse.fileContent ), true );
    parseResult( result );
    return result;
  }

  private any function makeHttpRequest( required string urlPath, required array params, required string method ) {
    var http = new http( url = urlPath, method = method, username = variables.apiKey, password = variables.apiSecret, timeout = variables.httpTimeout );

    // adding a user agent header so that Adobe ColdFusion doesn't get mad about empty HTTP posts
    http.addParam( type = "header", name = "User-Agent", value = "salesforceIQ.cfc" );

    var qs = [ ];

    for ( var param in params ) {

      if ( method == "post" ) {
        if ( arraycontains( variables.fileFields , param.name ) ) {
          http.addParam( type = "file", name = lcase( param.name ), file = param.value );
        } else {
          http.addParam( type = "formfield", name = lcase( param.name ), value = param.value );
        }
      } else if ( arrayFind( [ "get","delete" ], method ) ) {
        arrayAppend( qs, lcase( param.name ) & "=" & encodeurl( param.value ) );
      }

    }

    if ( arrayLen( qs ) ) {
      http.setUrl( urlPath & "?" & arrayToList( qs, "&" ) );
    }

    return http.send().getPrefix();
  }

  private array function setupParams( required struct params ) {
    var filteredParams = { };
    var paramKeys = structKeyArray( params );
    for ( var paramKey in paramKeys ) {
      if ( structKeyExists( params, paramKey ) && !isNull( params[ paramKey ] ) ) {
        filteredParams[ paramKey ] = params[ paramKey ];
      }
    }

    return parseDictionary( filteredParams );
  }

  private array function parseDictionary( required struct dictionary, string name = '', string root = '' ) {
    var result = [ ];
    var structFieldExists = structKeyExists( variables.dictionaryFields, name );

    // validate required dictionary keys based on variables.dictionaries
    if ( structFieldExists ) {
      for ( var field in variables.dictionaryFields[ name ].required ) {
        if ( !structKeyExists( dictionary, field ) ) {
          throwError( "'#name#' dictionary missing required field: #field#" );
        }
      }
    }

    for ( var key in dictionary ) {

      // confirm that key is a valid one based on variables.dictionaries
      if ( structFieldExists && !( arrayFindNoCase( variables.dictionaryFields[ name ].required, key ) || arrayFindNoCase( variables.dictionaryFields[ name ].optional, key ) ) ) {
        throwError( "'#name#' dictionary has invalid field: #key#" );
      }

      var fullKey = len( root ) ? root & ':' & lcase( key ) : lcase( key );
      if ( isStruct( dictionary[ key ] ) ) {
        for ( var item in parseDictionary( dictionary[ key ], key, fullKey ) ) {
          arrayAppend( result, item );
        }
      } else if ( isArray( dictionary[ key ] ) ) {
        for ( var item in parseArray( dictionary[ key ], key, fullKey ) ) {
          arrayAppend( result, item );
        }
      } else {
        // note: for now, the validate param passed into getValidatedParam() is always true, but that can be modified, if necessary
        arrayAppend( result, { name = fullKey, value = getValidatedParam( key, dictionary[ key ], true ) } );
      }

    }

    return result;
  }

  private array function parseArray( required array list, string name = '', string root = '' ) {
    var result = [ ];
    var index = 0;
    var arrayFieldExists = arrayFindNoCase( variables.arrayFields, name );

    if ( !arrayFieldExists ) {
      throwError( "'#name#' is not an allowed list variable." );
    }

    for ( var item in list ) {
      if ( isStruct( item ) ) {
        var fullKey = len( root ) ? root & "[" & index & "]" : name & "[" & index & "]";
        for ( var item in parseDictionary( item, '', fullKey ) ) {
          arrayAppend( result, item );
        }
        ++index;
      } else {
        var fullKey = len( root ) ? root : name;
        arrayAppend( result, { name = fullKey, value = getValidatedParam( name, item ) } );
      }
    }

    return result;
  }

  private any function getValidatedParam( required string paramName, required any paramValue, boolean validate = true ) {
    // only simple values
    if ( !isSimpleValue( paramValue ) ) throwError( "'#paramName#' is not a simple value." );

    // if not validation just result trimmed value
    if ( !validate ) {
      return trim( paramValue );
    }

    // integer
    if ( arrayFindNoCase( variables.integerFields, paramName ) ) {
      if ( !isInteger( paramValue ) ) {
        throwError( "field '#paramName#' requires an integer value" );
      }
      return paramValue;
    }
    // numeric
    if ( arrayFindNoCase( variables.numericFields, paramName ) ) {
      if ( !isNumeric( paramValue ) ) {
        throwError( "field '#paramName#' requires a numeric value" );
      }
      return paramValue;
    }

    // boolean
    if ( arrayFindNoCase( variables.booleanFields, paramName ) ) {
      return ( paramValue ? "true" : "false" );
    }

    // timestamp
    if ( arrayFindNoCase( variables.timestampFields, paramName ) ) {
      return parseUTCTimestampField( paramValue, paramName );
    }

    // default is string
    return trim( paramValue );
  }

  private void function parseResult( required struct result ) {
    var resultKeys = structKeyArray( result );
    for ( var key in resultKeys ) {
      if ( structKeyExists( result, key ) && !isNull( result[ key ] ) ) {
        if ( isStruct( result[ key ] ) ) parseResult( result[ key ] );
        if ( isArray( result[ key ] ) ) {
          for ( var item in result[ key ] ) {
            if ( isStruct( item ) ) parseResult( item );
          }
        }
        if ( arrayFindNoCase( variables.timestampFields, key ) ) result[ key ] = parseUTCTimestamp( result[ key ] );
      }
    }
  }

  private any function parseUTCTimestampField( required any utcField, required string utcFieldName ) {
    if ( isInteger( utcField ) ) return utcField;
    if ( isDate( utcField ) ) return getUTCTimestamp( utcField );
    throwError( "utc timestamp field '#utcFieldName#' is in an invalid format" );
  }

  private numeric function getUTCTimestamp( required date dateToConvert ) {
    return dateDiff( "s", variables.utcBaseDate, (dateToConvert*1000) );
  }

  private date function parseUTCTimestamp( required numeric utcTimestamp ) {
    return dateAdd( "s", (utcTimestamp/1000), variables.utcBaseDate );
  }

  private boolean function isInteger( required any varToValidate ) {
    return ( isNumeric( varToValidate ) && isValid( "integer", varToValidate ) );
  }

  private string function encodeurl( required string str ) {
    return replacelist( urlEncodedFormat( str, "utf-8" ), "%2D,%2E,%5F,%7E", "-,.,_,~" );
  }

  private void function throwError( required string errorMessage ) {
    throw( type = "SalesForceIQ", message = "(salesforceIQ.cfc) " & errorMessage );
  }

}