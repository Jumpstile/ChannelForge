// Generated from schemas/one-guide-projection.schema.json. Do not edit.
import * as formatsModule from 'ajv-formats/dist/formats.js'
const formats = formatsModule.default ?? formatsModule
import { default as ajvRuntime0Module } from 'ajv/dist/runtime/ucs2length.js'
const ajvRuntime0 = ajvRuntime0Module.default ?? ajvRuntime0Module
import { default as ajvRuntime1Module } from 'ajv/dist/runtime/equal.js'
const ajvRuntime1 = ajvRuntime1Module.default ?? ajvRuntime1Module
export const validate = validate20;
export default validate20;
const schema31 = {"$schema":"https://json-schema.org/draft/2020-12/schema","$id":"https://channelforge.invalid/schemas/one-guide-projection.schema.json","title":"ChannelForge One Guide read projection","description":"Bounded, deterministic, read-only projection of accepted XMLTV. Cross-channel grouping, source provenance, and programme Kind are exposed only when preserved by input evidence.","type":"object","additionalProperties":false,"required":["Version","EvaluationTimeUtc","Query","Offset","MaximumItems","TotalCount","ItemsTruncated","Items"],"properties":{"Version":{"const":"one-guide/v1"},"EvaluationTimeUtc":{"type":"string","format":"date-time"},"Query":{"enum":["LiveNow","StartingSoon","Category","Details"]},"CategoryKey":{"enum":["live-now","starting-soon","football","baseball","basketball","hockey","soccer","wrestling","motorsports","boxing","mma","tennis","golf","rugby","cricket","lacrosse","other-sports","movies","news","kids","entertainment","documentary","comedy"]},"Offset":{"type":"integer","minimum":0},"MaximumItems":{"type":"integer","minimum":1,"maximum":100},"TotalCount":{"type":"integer","minimum":0},"ItemsTruncated":{"type":"boolean"},"Items":{"type":"array","maxItems":100,"items":{"$ref":"#/$defs/item"}}},"$defs":{"categoryKey":{"enum":["live-now","starting-soon","football","baseball","basketball","hockey","soccer","wrestling","motorsports","boxing","mma","tennis","golf","rugby","cricket","lacrosse","other-sports","movies","news","kids","entertainment","documentary","comedy"]},"item":{"type":"object","additionalProperties":false,"required":["ItemId","Kind","Title","StartUtc","StopUtc","Status","CategoryKeys","Sport","League","HomeParticipant","AwayParticipant","Promotion","Offerings","OfferingCount","OfferingsTruncated","FreshnessState","ConfidenceState","ConfidenceScore"],"properties":{"ItemId":{"type":"string","pattern":"^[a-f0-9]{64}$"},"Kind":{"enum":["Programme","Event","Movie","SeriesEpisode","Other"]},"Title":{"type":"string","minLength":1,"maxLength":256},"Subtitle":{"type":["string","null"],"maxLength":256},"Description":{"type":["string","null"],"maxLength":512},"EpisodeNumber":{"type":["string","null"],"maxLength":128},"StartUtc":{"type":"string","format":"date-time"},"StopUtc":{"type":"string","format":"date-time"},"Status":{"enum":["Live","StartingSoon","Upcoming","Past"]},"CategoryKeys":{"type":"array","uniqueItems":true,"items":{"$ref":"#/$defs/categoryKey"}},"Sport":{"type":["string","null"],"maxLength":128},"League":{"type":["string","null"],"maxLength":128},"HomeParticipant":{"type":["string","null"],"maxLength":128},"AwayParticipant":{"type":["string","null"],"maxLength":128},"Promotion":{"anyOf":[{"type":"null"},{"type":"object","additionalProperties":false,"required":["Id","Name"],"properties":{"Id":{"type":"string","pattern":"^cf-[a-f0-9]{64}$"},"Name":{"type":"string","minLength":1,"maxLength":128}}}]},"OfferingCount":{"type":"integer","minimum":1},"OfferingsTruncated":{"type":"boolean"},"Offerings":{"type":"array","minItems":1,"maxItems":16,"items":{"type":"object","additionalProperties":false,"required":["OfferingId","SourceId","SourceLabel","Availability","Entitlement","Launch","DvrSupported","TimeshiftSupported"],"properties":{"OfferingId":{"type":"string","pattern":"^[a-f0-9]{64}$"},"SourceId":{"type":"string","pattern":"^cf-[a-f0-9]{64}$"},"SourceLabel":{"type":"string","minLength":1,"maxLength":128},"Availability":{"const":"GuideOnly"},"Entitlement":{"const":"Unknown"},"Launch":{"type":"object","additionalProperties":false,"required":["Kind","ChannelReference"],"properties":{"Kind":{"const":"Channel"},"ChannelReference":{"type":"string","pattern":"^cf-[a-f0-9]{64}$"}}},"DvrSupported":{"type":["boolean","null"]},"TimeshiftSupported":{"type":["boolean","null"]}}}},"FreshnessState":{"enum":["Current","Stale","Unavailable","Unknown"]},"ConfidenceState":{"enum":["Confirmed","NeedsReview","Unknown"]},"ConfidenceScore":{"type":["integer","null"],"minimum":0,"maximum":100}}}}};
const func1 = Object.prototype.hasOwnProperty;
const formats0 = formats.fullFormats["date-time"];
const schema32 = {"type":"object","additionalProperties":false,"required":["ItemId","Kind","Title","StartUtc","StopUtc","Status","CategoryKeys","Sport","League","HomeParticipant","AwayParticipant","Promotion","Offerings","OfferingCount","OfferingsTruncated","FreshnessState","ConfidenceState","ConfidenceScore"],"properties":{"ItemId":{"type":"string","pattern":"^[a-f0-9]{64}$"},"Kind":{"enum":["Programme","Event","Movie","SeriesEpisode","Other"]},"Title":{"type":"string","minLength":1,"maxLength":256},"Subtitle":{"type":["string","null"],"maxLength":256},"Description":{"type":["string","null"],"maxLength":512},"EpisodeNumber":{"type":["string","null"],"maxLength":128},"StartUtc":{"type":"string","format":"date-time"},"StopUtc":{"type":"string","format":"date-time"},"Status":{"enum":["Live","StartingSoon","Upcoming","Past"]},"CategoryKeys":{"type":"array","uniqueItems":true,"items":{"$ref":"#/$defs/categoryKey"}},"Sport":{"type":["string","null"],"maxLength":128},"League":{"type":["string","null"],"maxLength":128},"HomeParticipant":{"type":["string","null"],"maxLength":128},"AwayParticipant":{"type":["string","null"],"maxLength":128},"Promotion":{"anyOf":[{"type":"null"},{"type":"object","additionalProperties":false,"required":["Id","Name"],"properties":{"Id":{"type":"string","pattern":"^cf-[a-f0-9]{64}$"},"Name":{"type":"string","minLength":1,"maxLength":128}}}]},"OfferingCount":{"type":"integer","minimum":1},"OfferingsTruncated":{"type":"boolean"},"Offerings":{"type":"array","minItems":1,"maxItems":16,"items":{"type":"object","additionalProperties":false,"required":["OfferingId","SourceId","SourceLabel","Availability","Entitlement","Launch","DvrSupported","TimeshiftSupported"],"properties":{"OfferingId":{"type":"string","pattern":"^[a-f0-9]{64}$"},"SourceId":{"type":"string","pattern":"^cf-[a-f0-9]{64}$"},"SourceLabel":{"type":"string","minLength":1,"maxLength":128},"Availability":{"const":"GuideOnly"},"Entitlement":{"const":"Unknown"},"Launch":{"type":"object","additionalProperties":false,"required":["Kind","ChannelReference"],"properties":{"Kind":{"const":"Channel"},"ChannelReference":{"type":"string","pattern":"^cf-[a-f0-9]{64}$"}}},"DvrSupported":{"type":["boolean","null"]},"TimeshiftSupported":{"type":["boolean","null"]}}}},"FreshnessState":{"enum":["Current","Stale","Unavailable","Unknown"]},"ConfidenceState":{"enum":["Confirmed","NeedsReview","Unknown"]},"ConfidenceScore":{"type":["integer","null"],"minimum":0,"maximum":100}}};
const schema33 = {"enum":["live-now","starting-soon","football","baseball","basketball","hockey","soccer","wrestling","motorsports","boxing","mma","tennis","golf","rugby","cricket","lacrosse","other-sports","movies","news","kids","entertainment","documentary","comedy"]};
const func3 = ajvRuntime0;
const func0 = ajvRuntime1;
const pattern4 = new RegExp("^[a-f0-9]{64}$", "u");
const pattern5 = new RegExp("^cf-[a-f0-9]{64}$", "u");

function validate21(data, {instancePath="", parentData, parentDataProperty, rootData=data, dynamicAnchors={}}={}){
let vErrors = null;
let errors = 0;
const evaluated0 = validate21.evaluated;
if(evaluated0.dynamicProps){
evaluated0.props = undefined;
}
if(evaluated0.dynamicItems){
evaluated0.items = undefined;
}
if(errors === 0){
if(data && typeof data == "object" && !Array.isArray(data)){
let missing0;
if(((((((((((((((((((data.ItemId === undefined) && (missing0 = "ItemId")) || ((data.Kind === undefined) && (missing0 = "Kind"))) || ((data.Title === undefined) && (missing0 = "Title"))) || ((data.StartUtc === undefined) && (missing0 = "StartUtc"))) || ((data.StopUtc === undefined) && (missing0 = "StopUtc"))) || ((data.Status === undefined) && (missing0 = "Status"))) || ((data.CategoryKeys === undefined) && (missing0 = "CategoryKeys"))) || ((data.Sport === undefined) && (missing0 = "Sport"))) || ((data.League === undefined) && (missing0 = "League"))) || ((data.HomeParticipant === undefined) && (missing0 = "HomeParticipant"))) || ((data.AwayParticipant === undefined) && (missing0 = "AwayParticipant"))) || ((data.Promotion === undefined) && (missing0 = "Promotion"))) || ((data.Offerings === undefined) && (missing0 = "Offerings"))) || ((data.OfferingCount === undefined) && (missing0 = "OfferingCount"))) || ((data.OfferingsTruncated === undefined) && (missing0 = "OfferingsTruncated"))) || ((data.FreshnessState === undefined) && (missing0 = "FreshnessState"))) || ((data.ConfidenceState === undefined) && (missing0 = "ConfidenceState"))) || ((data.ConfidenceScore === undefined) && (missing0 = "ConfidenceScore"))){
validate21.errors = [{instancePath,schemaPath:"#/required",keyword:"required",params:{missingProperty: missing0},message:"must have required property '"+missing0+"'"}];
return false;
}
else {
const _errs1 = errors;
for(const key0 in data){
if(!(func1.call(schema32.properties, key0))){
validate21.errors = [{instancePath,schemaPath:"#/additionalProperties",keyword:"additionalProperties",params:{additionalProperty: key0},message:"must NOT have additional properties"}];
return false;
break;
}
}
if(_errs1 === errors){
if(data.ItemId !== undefined){
let data0 = data.ItemId;
const _errs2 = errors;
if(errors === _errs2){
if(typeof data0 === "string"){
if(!pattern4.test(data0)){
validate21.errors = [{instancePath:instancePath+"/ItemId",schemaPath:"#/properties/ItemId/pattern",keyword:"pattern",params:{pattern: "^[a-f0-9]{64}$"},message:"must match pattern \""+"^[a-f0-9]{64}$"+"\""}];
return false;
}
}
else {
validate21.errors = [{instancePath:instancePath+"/ItemId",schemaPath:"#/properties/ItemId/type",keyword:"type",params:{type: "string"},message:"must be string"}];
return false;
}
}
var valid0 = _errs2 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.Kind !== undefined){
let data1 = data.Kind;
const _errs4 = errors;
if(!(((((data1 === "Programme") || (data1 === "Event")) || (data1 === "Movie")) || (data1 === "SeriesEpisode")) || (data1 === "Other"))){
validate21.errors = [{instancePath:instancePath+"/Kind",schemaPath:"#/properties/Kind/enum",keyword:"enum",params:{allowedValues: schema32.properties.Kind.enum},message:"must be equal to one of the allowed values"}];
return false;
}
var valid0 = _errs4 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.Title !== undefined){
let data2 = data.Title;
const _errs5 = errors;
if(errors === _errs5){
if(typeof data2 === "string"){
if(func3(data2) > 256){
validate21.errors = [{instancePath:instancePath+"/Title",schemaPath:"#/properties/Title/maxLength",keyword:"maxLength",params:{limit: 256},message:"must NOT have more than 256 characters"}];
return false;
}
else {
if(func3(data2) < 1){
validate21.errors = [{instancePath:instancePath+"/Title",schemaPath:"#/properties/Title/minLength",keyword:"minLength",params:{limit: 1},message:"must NOT have fewer than 1 characters"}];
return false;
}
}
}
else {
validate21.errors = [{instancePath:instancePath+"/Title",schemaPath:"#/properties/Title/type",keyword:"type",params:{type: "string"},message:"must be string"}];
return false;
}
}
var valid0 = _errs5 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.Subtitle !== undefined){
let data3 = data.Subtitle;
const _errs7 = errors;
if((typeof data3 !== "string") && (data3 !== null)){
validate21.errors = [{instancePath:instancePath+"/Subtitle",schemaPath:"#/properties/Subtitle/type",keyword:"type",params:{type: schema32.properties.Subtitle.type},message:"must be string,null"}];
return false;
}
if(errors === _errs7){
if(typeof data3 === "string"){
if(func3(data3) > 256){
validate21.errors = [{instancePath:instancePath+"/Subtitle",schemaPath:"#/properties/Subtitle/maxLength",keyword:"maxLength",params:{limit: 256},message:"must NOT have more than 256 characters"}];
return false;
}
}
}
var valid0 = _errs7 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.Description !== undefined){
let data4 = data.Description;
const _errs9 = errors;
if((typeof data4 !== "string") && (data4 !== null)){
validate21.errors = [{instancePath:instancePath+"/Description",schemaPath:"#/properties/Description/type",keyword:"type",params:{type: schema32.properties.Description.type},message:"must be string,null"}];
return false;
}
if(errors === _errs9){
if(typeof data4 === "string"){
if(func3(data4) > 512){
validate21.errors = [{instancePath:instancePath+"/Description",schemaPath:"#/properties/Description/maxLength",keyword:"maxLength",params:{limit: 512},message:"must NOT have more than 512 characters"}];
return false;
}
}
}
var valid0 = _errs9 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.EpisodeNumber !== undefined){
let data5 = data.EpisodeNumber;
const _errs11 = errors;
if((typeof data5 !== "string") && (data5 !== null)){
validate21.errors = [{instancePath:instancePath+"/EpisodeNumber",schemaPath:"#/properties/EpisodeNumber/type",keyword:"type",params:{type: schema32.properties.EpisodeNumber.type},message:"must be string,null"}];
return false;
}
if(errors === _errs11){
if(typeof data5 === "string"){
if(func3(data5) > 128){
validate21.errors = [{instancePath:instancePath+"/EpisodeNumber",schemaPath:"#/properties/EpisodeNumber/maxLength",keyword:"maxLength",params:{limit: 128},message:"must NOT have more than 128 characters"}];
return false;
}
}
}
var valid0 = _errs11 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.StartUtc !== undefined){
let data6 = data.StartUtc;
const _errs13 = errors;
if(errors === _errs13){
if(errors === _errs13){
if(typeof data6 === "string"){
if(!(formats0.validate(data6))){
validate21.errors = [{instancePath:instancePath+"/StartUtc",schemaPath:"#/properties/StartUtc/format",keyword:"format",params:{format: "date-time"},message:"must match format \""+"date-time"+"\""}];
return false;
}
}
else {
validate21.errors = [{instancePath:instancePath+"/StartUtc",schemaPath:"#/properties/StartUtc/type",keyword:"type",params:{type: "string"},message:"must be string"}];
return false;
}
}
}
var valid0 = _errs13 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.StopUtc !== undefined){
let data7 = data.StopUtc;
const _errs15 = errors;
if(errors === _errs15){
if(errors === _errs15){
if(typeof data7 === "string"){
if(!(formats0.validate(data7))){
validate21.errors = [{instancePath:instancePath+"/StopUtc",schemaPath:"#/properties/StopUtc/format",keyword:"format",params:{format: "date-time"},message:"must match format \""+"date-time"+"\""}];
return false;
}
}
else {
validate21.errors = [{instancePath:instancePath+"/StopUtc",schemaPath:"#/properties/StopUtc/type",keyword:"type",params:{type: "string"},message:"must be string"}];
return false;
}
}
}
var valid0 = _errs15 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.Status !== undefined){
let data8 = data.Status;
const _errs17 = errors;
if(!((((data8 === "Live") || (data8 === "StartingSoon")) || (data8 === "Upcoming")) || (data8 === "Past"))){
validate21.errors = [{instancePath:instancePath+"/Status",schemaPath:"#/properties/Status/enum",keyword:"enum",params:{allowedValues: schema32.properties.Status.enum},message:"must be equal to one of the allowed values"}];
return false;
}
var valid0 = _errs17 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.CategoryKeys !== undefined){
let data9 = data.CategoryKeys;
const _errs18 = errors;
if(errors === _errs18){
if(Array.isArray(data9)){
var valid1 = true;
const len0 = data9.length;
for(let i0=0; i0<len0; i0++){
let data10 = data9[i0];
const _errs20 = errors;
if(!(((((((((((((((((((((((data10 === "live-now") || (data10 === "starting-soon")) || (data10 === "football")) || (data10 === "baseball")) || (data10 === "basketball")) || (data10 === "hockey")) || (data10 === "soccer")) || (data10 === "wrestling")) || (data10 === "motorsports")) || (data10 === "boxing")) || (data10 === "mma")) || (data10 === "tennis")) || (data10 === "golf")) || (data10 === "rugby")) || (data10 === "cricket")) || (data10 === "lacrosse")) || (data10 === "other-sports")) || (data10 === "movies")) || (data10 === "news")) || (data10 === "kids")) || (data10 === "entertainment")) || (data10 === "documentary")) || (data10 === "comedy"))){
validate21.errors = [{instancePath:instancePath+"/CategoryKeys/" + i0,schemaPath:"#/$defs/categoryKey/enum",keyword:"enum",params:{allowedValues: schema33.enum},message:"must be equal to one of the allowed values"}];
return false;
}
var valid1 = _errs20 === errors;
if(!valid1){
break;
}
}
if(valid1){
let i1 = data9.length;
let j0;
if(i1 > 1){
outer0:
for(;i1--;){
for(j0 = i1; j0--;){
if(func0(data9[i1], data9[j0])){
validate21.errors = [{instancePath:instancePath+"/CategoryKeys",schemaPath:"#/properties/CategoryKeys/uniqueItems",keyword:"uniqueItems",params:{i: i1, j: j0},message:"must NOT have duplicate items (items ## "+j0+" and "+i1+" are identical)"}];
return false;
break outer0;
}
}
}
}
}
}
else {
validate21.errors = [{instancePath:instancePath+"/CategoryKeys",schemaPath:"#/properties/CategoryKeys/type",keyword:"type",params:{type: "array"},message:"must be array"}];
return false;
}
}
var valid0 = _errs18 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.Sport !== undefined){
let data11 = data.Sport;
const _errs22 = errors;
if((typeof data11 !== "string") && (data11 !== null)){
validate21.errors = [{instancePath:instancePath+"/Sport",schemaPath:"#/properties/Sport/type",keyword:"type",params:{type: schema32.properties.Sport.type},message:"must be string,null"}];
return false;
}
if(errors === _errs22){
if(typeof data11 === "string"){
if(func3(data11) > 128){
validate21.errors = [{instancePath:instancePath+"/Sport",schemaPath:"#/properties/Sport/maxLength",keyword:"maxLength",params:{limit: 128},message:"must NOT have more than 128 characters"}];
return false;
}
}
}
var valid0 = _errs22 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.League !== undefined){
let data12 = data.League;
const _errs24 = errors;
if((typeof data12 !== "string") && (data12 !== null)){
validate21.errors = [{instancePath:instancePath+"/League",schemaPath:"#/properties/League/type",keyword:"type",params:{type: schema32.properties.League.type},message:"must be string,null"}];
return false;
}
if(errors === _errs24){
if(typeof data12 === "string"){
if(func3(data12) > 128){
validate21.errors = [{instancePath:instancePath+"/League",schemaPath:"#/properties/League/maxLength",keyword:"maxLength",params:{limit: 128},message:"must NOT have more than 128 characters"}];
return false;
}
}
}
var valid0 = _errs24 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.HomeParticipant !== undefined){
let data13 = data.HomeParticipant;
const _errs26 = errors;
if((typeof data13 !== "string") && (data13 !== null)){
validate21.errors = [{instancePath:instancePath+"/HomeParticipant",schemaPath:"#/properties/HomeParticipant/type",keyword:"type",params:{type: schema32.properties.HomeParticipant.type},message:"must be string,null"}];
return false;
}
if(errors === _errs26){
if(typeof data13 === "string"){
if(func3(data13) > 128){
validate21.errors = [{instancePath:instancePath+"/HomeParticipant",schemaPath:"#/properties/HomeParticipant/maxLength",keyword:"maxLength",params:{limit: 128},message:"must NOT have more than 128 characters"}];
return false;
}
}
}
var valid0 = _errs26 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.AwayParticipant !== undefined){
let data14 = data.AwayParticipant;
const _errs28 = errors;
if((typeof data14 !== "string") && (data14 !== null)){
validate21.errors = [{instancePath:instancePath+"/AwayParticipant",schemaPath:"#/properties/AwayParticipant/type",keyword:"type",params:{type: schema32.properties.AwayParticipant.type},message:"must be string,null"}];
return false;
}
if(errors === _errs28){
if(typeof data14 === "string"){
if(func3(data14) > 128){
validate21.errors = [{instancePath:instancePath+"/AwayParticipant",schemaPath:"#/properties/AwayParticipant/maxLength",keyword:"maxLength",params:{limit: 128},message:"must NOT have more than 128 characters"}];
return false;
}
}
}
var valid0 = _errs28 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.Promotion !== undefined){
let data15 = data.Promotion;
const _errs30 = errors;
const _errs31 = errors;
let valid4 = false;
const _errs32 = errors;
if(data15 !== null){
const err0 = {instancePath:instancePath+"/Promotion",schemaPath:"#/properties/Promotion/anyOf/0/type",keyword:"type",params:{type: "null"},message:"must be null"};
if(vErrors === null){
vErrors = [err0];
}
else {
vErrors.push(err0);
}
errors++;
}
var _valid0 = _errs32 === errors;
valid4 = valid4 || _valid0;
const _errs34 = errors;
if(errors === _errs34){
if(data15 && typeof data15 == "object" && !Array.isArray(data15)){
let missing1;
if(((data15.Id === undefined) && (missing1 = "Id")) || ((data15.Name === undefined) && (missing1 = "Name"))){
const err1 = {instancePath:instancePath+"/Promotion",schemaPath:"#/properties/Promotion/anyOf/1/required",keyword:"required",params:{missingProperty: missing1},message:"must have required property '"+missing1+"'"};
if(vErrors === null){
vErrors = [err1];
}
else {
vErrors.push(err1);
}
errors++;
}
else {
const _errs36 = errors;
for(const key1 in data15){
if(!((key1 === "Id") || (key1 === "Name"))){
const err2 = {instancePath:instancePath+"/Promotion",schemaPath:"#/properties/Promotion/anyOf/1/additionalProperties",keyword:"additionalProperties",params:{additionalProperty: key1},message:"must NOT have additional properties"};
if(vErrors === null){
vErrors = [err2];
}
else {
vErrors.push(err2);
}
errors++;
break;
}
}
if(_errs36 === errors){
if(data15.Id !== undefined){
let data16 = data15.Id;
const _errs37 = errors;
if(errors === _errs37){
if(typeof data16 === "string"){
if(!pattern5.test(data16)){
const err3 = {instancePath:instancePath+"/Promotion/Id",schemaPath:"#/properties/Promotion/anyOf/1/properties/Id/pattern",keyword:"pattern",params:{pattern: "^cf-[a-f0-9]{64}$"},message:"must match pattern \""+"^cf-[a-f0-9]{64}$"+"\""};
if(vErrors === null){
vErrors = [err3];
}
else {
vErrors.push(err3);
}
errors++;
}
}
else {
const err4 = {instancePath:instancePath+"/Promotion/Id",schemaPath:"#/properties/Promotion/anyOf/1/properties/Id/type",keyword:"type",params:{type: "string"},message:"must be string"};
if(vErrors === null){
vErrors = [err4];
}
else {
vErrors.push(err4);
}
errors++;
}
}
var valid5 = _errs37 === errors;
}
else {
var valid5 = true;
}
if(valid5){
if(data15.Name !== undefined){
let data17 = data15.Name;
const _errs39 = errors;
if(errors === _errs39){
if(typeof data17 === "string"){
if(func3(data17) > 128){
const err5 = {instancePath:instancePath+"/Promotion/Name",schemaPath:"#/properties/Promotion/anyOf/1/properties/Name/maxLength",keyword:"maxLength",params:{limit: 128},message:"must NOT have more than 128 characters"};
if(vErrors === null){
vErrors = [err5];
}
else {
vErrors.push(err5);
}
errors++;
}
else {
if(func3(data17) < 1){
const err6 = {instancePath:instancePath+"/Promotion/Name",schemaPath:"#/properties/Promotion/anyOf/1/properties/Name/minLength",keyword:"minLength",params:{limit: 1},message:"must NOT have fewer than 1 characters"};
if(vErrors === null){
vErrors = [err6];
}
else {
vErrors.push(err6);
}
errors++;
}
}
}
else {
const err7 = {instancePath:instancePath+"/Promotion/Name",schemaPath:"#/properties/Promotion/anyOf/1/properties/Name/type",keyword:"type",params:{type: "string"},message:"must be string"};
if(vErrors === null){
vErrors = [err7];
}
else {
vErrors.push(err7);
}
errors++;
}
}
var valid5 = _errs39 === errors;
}
else {
var valid5 = true;
}
}
}
}
}
else {
const err8 = {instancePath:instancePath+"/Promotion",schemaPath:"#/properties/Promotion/anyOf/1/type",keyword:"type",params:{type: "object"},message:"must be object"};
if(vErrors === null){
vErrors = [err8];
}
else {
vErrors.push(err8);
}
errors++;
}
}
var _valid0 = _errs34 === errors;
valid4 = valid4 || _valid0;
if(!valid4){
const err9 = {instancePath:instancePath+"/Promotion",schemaPath:"#/properties/Promotion/anyOf",keyword:"anyOf",params:{},message:"must match a schema in anyOf"};
if(vErrors === null){
vErrors = [err9];
}
else {
vErrors.push(err9);
}
errors++;
validate21.errors = vErrors;
return false;
}
else {
errors = _errs31;
if(vErrors !== null){
if(_errs31){
vErrors.length = _errs31;
}
else {
vErrors = null;
}
}
}
var valid0 = _errs30 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.OfferingCount !== undefined){
let data18 = data.OfferingCount;
const _errs41 = errors;
if(!(((typeof data18 == "number") && (!(data18 % 1) && !isNaN(data18))) && (isFinite(data18)))){
validate21.errors = [{instancePath:instancePath+"/OfferingCount",schemaPath:"#/properties/OfferingCount/type",keyword:"type",params:{type: "integer"},message:"must be integer"}];
return false;
}
if(errors === _errs41){
if((typeof data18 == "number") && (isFinite(data18))){
if(data18 < 1 || isNaN(data18)){
validate21.errors = [{instancePath:instancePath+"/OfferingCount",schemaPath:"#/properties/OfferingCount/minimum",keyword:"minimum",params:{comparison: ">=", limit: 1},message:"must be >= 1"}];
return false;
}
}
}
var valid0 = _errs41 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.OfferingsTruncated !== undefined){
const _errs43 = errors;
if(typeof data.OfferingsTruncated !== "boolean"){
validate21.errors = [{instancePath:instancePath+"/OfferingsTruncated",schemaPath:"#/properties/OfferingsTruncated/type",keyword:"type",params:{type: "boolean"},message:"must be boolean"}];
return false;
}
var valid0 = _errs43 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.Offerings !== undefined){
let data20 = data.Offerings;
const _errs45 = errors;
if(errors === _errs45){
if(Array.isArray(data20)){
if(data20.length > 16){
validate21.errors = [{instancePath:instancePath+"/Offerings",schemaPath:"#/properties/Offerings/maxItems",keyword:"maxItems",params:{limit: 16},message:"must NOT have more than 16 items"}];
return false;
}
else {
if(data20.length < 1){
validate21.errors = [{instancePath:instancePath+"/Offerings",schemaPath:"#/properties/Offerings/minItems",keyword:"minItems",params:{limit: 1},message:"must NOT have fewer than 1 items"}];
return false;
}
else {
var valid6 = true;
const len1 = data20.length;
for(let i2=0; i2<len1; i2++){
let data21 = data20[i2];
const _errs47 = errors;
if(errors === _errs47){
if(data21 && typeof data21 == "object" && !Array.isArray(data21)){
let missing2;
if(((((((((data21.OfferingId === undefined) && (missing2 = "OfferingId")) || ((data21.SourceId === undefined) && (missing2 = "SourceId"))) || ((data21.SourceLabel === undefined) && (missing2 = "SourceLabel"))) || ((data21.Availability === undefined) && (missing2 = "Availability"))) || ((data21.Entitlement === undefined) && (missing2 = "Entitlement"))) || ((data21.Launch === undefined) && (missing2 = "Launch"))) || ((data21.DvrSupported === undefined) && (missing2 = "DvrSupported"))) || ((data21.TimeshiftSupported === undefined) && (missing2 = "TimeshiftSupported"))){
validate21.errors = [{instancePath:instancePath+"/Offerings/" + i2,schemaPath:"#/properties/Offerings/items/required",keyword:"required",params:{missingProperty: missing2},message:"must have required property '"+missing2+"'"}];
return false;
}
else {
const _errs49 = errors;
for(const key2 in data21){
if(!((((((((key2 === "OfferingId") || (key2 === "SourceId")) || (key2 === "SourceLabel")) || (key2 === "Availability")) || (key2 === "Entitlement")) || (key2 === "Launch")) || (key2 === "DvrSupported")) || (key2 === "TimeshiftSupported"))){
validate21.errors = [{instancePath:instancePath+"/Offerings/" + i2,schemaPath:"#/properties/Offerings/items/additionalProperties",keyword:"additionalProperties",params:{additionalProperty: key2},message:"must NOT have additional properties"}];
return false;
break;
}
}
if(_errs49 === errors){
if(data21.OfferingId !== undefined){
let data22 = data21.OfferingId;
const _errs50 = errors;
if(errors === _errs50){
if(typeof data22 === "string"){
if(!pattern4.test(data22)){
validate21.errors = [{instancePath:instancePath+"/Offerings/" + i2+"/OfferingId",schemaPath:"#/properties/Offerings/items/properties/OfferingId/pattern",keyword:"pattern",params:{pattern: "^[a-f0-9]{64}$"},message:"must match pattern \""+"^[a-f0-9]{64}$"+"\""}];
return false;
}
}
else {
validate21.errors = [{instancePath:instancePath+"/Offerings/" + i2+"/OfferingId",schemaPath:"#/properties/Offerings/items/properties/OfferingId/type",keyword:"type",params:{type: "string"},message:"must be string"}];
return false;
}
}
var valid7 = _errs50 === errors;
}
else {
var valid7 = true;
}
if(valid7){
if(data21.SourceId !== undefined){
let data23 = data21.SourceId;
const _errs52 = errors;
if(errors === _errs52){
if(typeof data23 === "string"){
if(!pattern5.test(data23)){
validate21.errors = [{instancePath:instancePath+"/Offerings/" + i2+"/SourceId",schemaPath:"#/properties/Offerings/items/properties/SourceId/pattern",keyword:"pattern",params:{pattern: "^cf-[a-f0-9]{64}$"},message:"must match pattern \""+"^cf-[a-f0-9]{64}$"+"\""}];
return false;
}
}
else {
validate21.errors = [{instancePath:instancePath+"/Offerings/" + i2+"/SourceId",schemaPath:"#/properties/Offerings/items/properties/SourceId/type",keyword:"type",params:{type: "string"},message:"must be string"}];
return false;
}
}
var valid7 = _errs52 === errors;
}
else {
var valid7 = true;
}
if(valid7){
if(data21.SourceLabel !== undefined){
let data24 = data21.SourceLabel;
const _errs54 = errors;
if(errors === _errs54){
if(typeof data24 === "string"){
if(func3(data24) > 128){
validate21.errors = [{instancePath:instancePath+"/Offerings/" + i2+"/SourceLabel",schemaPath:"#/properties/Offerings/items/properties/SourceLabel/maxLength",keyword:"maxLength",params:{limit: 128},message:"must NOT have more than 128 characters"}];
return false;
}
else {
if(func3(data24) < 1){
validate21.errors = [{instancePath:instancePath+"/Offerings/" + i2+"/SourceLabel",schemaPath:"#/properties/Offerings/items/properties/SourceLabel/minLength",keyword:"minLength",params:{limit: 1},message:"must NOT have fewer than 1 characters"}];
return false;
}
}
}
else {
validate21.errors = [{instancePath:instancePath+"/Offerings/" + i2+"/SourceLabel",schemaPath:"#/properties/Offerings/items/properties/SourceLabel/type",keyword:"type",params:{type: "string"},message:"must be string"}];
return false;
}
}
var valid7 = _errs54 === errors;
}
else {
var valid7 = true;
}
if(valid7){
if(data21.Availability !== undefined){
const _errs56 = errors;
if("GuideOnly" !== data21.Availability){
validate21.errors = [{instancePath:instancePath+"/Offerings/" + i2+"/Availability",schemaPath:"#/properties/Offerings/items/properties/Availability/const",keyword:"const",params:{allowedValue: "GuideOnly"},message:"must be equal to constant"}];
return false;
}
var valid7 = _errs56 === errors;
}
else {
var valid7 = true;
}
if(valid7){
if(data21.Entitlement !== undefined){
const _errs57 = errors;
if("Unknown" !== data21.Entitlement){
validate21.errors = [{instancePath:instancePath+"/Offerings/" + i2+"/Entitlement",schemaPath:"#/properties/Offerings/items/properties/Entitlement/const",keyword:"const",params:{allowedValue: "Unknown"},message:"must be equal to constant"}];
return false;
}
var valid7 = _errs57 === errors;
}
else {
var valid7 = true;
}
if(valid7){
if(data21.Launch !== undefined){
let data27 = data21.Launch;
const _errs58 = errors;
if(errors === _errs58){
if(data27 && typeof data27 == "object" && !Array.isArray(data27)){
let missing3;
if(((data27.Kind === undefined) && (missing3 = "Kind")) || ((data27.ChannelReference === undefined) && (missing3 = "ChannelReference"))){
validate21.errors = [{instancePath:instancePath+"/Offerings/" + i2+"/Launch",schemaPath:"#/properties/Offerings/items/properties/Launch/required",keyword:"required",params:{missingProperty: missing3},message:"must have required property '"+missing3+"'"}];
return false;
}
else {
const _errs60 = errors;
for(const key3 in data27){
if(!((key3 === "Kind") || (key3 === "ChannelReference"))){
validate21.errors = [{instancePath:instancePath+"/Offerings/" + i2+"/Launch",schemaPath:"#/properties/Offerings/items/properties/Launch/additionalProperties",keyword:"additionalProperties",params:{additionalProperty: key3},message:"must NOT have additional properties"}];
return false;
break;
}
}
if(_errs60 === errors){
if(data27.Kind !== undefined){
const _errs61 = errors;
if("Channel" !== data27.Kind){
validate21.errors = [{instancePath:instancePath+"/Offerings/" + i2+"/Launch/Kind",schemaPath:"#/properties/Offerings/items/properties/Launch/properties/Kind/const",keyword:"const",params:{allowedValue: "Channel"},message:"must be equal to constant"}];
return false;
}
var valid8 = _errs61 === errors;
}
else {
var valid8 = true;
}
if(valid8){
if(data27.ChannelReference !== undefined){
let data29 = data27.ChannelReference;
const _errs62 = errors;
if(errors === _errs62){
if(typeof data29 === "string"){
if(!pattern5.test(data29)){
validate21.errors = [{instancePath:instancePath+"/Offerings/" + i2+"/Launch/ChannelReference",schemaPath:"#/properties/Offerings/items/properties/Launch/properties/ChannelReference/pattern",keyword:"pattern",params:{pattern: "^cf-[a-f0-9]{64}$"},message:"must match pattern \""+"^cf-[a-f0-9]{64}$"+"\""}];
return false;
}
}
else {
validate21.errors = [{instancePath:instancePath+"/Offerings/" + i2+"/Launch/ChannelReference",schemaPath:"#/properties/Offerings/items/properties/Launch/properties/ChannelReference/type",keyword:"type",params:{type: "string"},message:"must be string"}];
return false;
}
}
var valid8 = _errs62 === errors;
}
else {
var valid8 = true;
}
}
}
}
}
else {
validate21.errors = [{instancePath:instancePath+"/Offerings/" + i2+"/Launch",schemaPath:"#/properties/Offerings/items/properties/Launch/type",keyword:"type",params:{type: "object"},message:"must be object"}];
return false;
}
}
var valid7 = _errs58 === errors;
}
else {
var valid7 = true;
}
if(valid7){
if(data21.DvrSupported !== undefined){
let data30 = data21.DvrSupported;
const _errs64 = errors;
if((typeof data30 !== "boolean") && (data30 !== null)){
validate21.errors = [{instancePath:instancePath+"/Offerings/" + i2+"/DvrSupported",schemaPath:"#/properties/Offerings/items/properties/DvrSupported/type",keyword:"type",params:{type: schema32.properties.Offerings.items.properties.DvrSupported.type},message:"must be boolean,null"}];
return false;
}
var valid7 = _errs64 === errors;
}
else {
var valid7 = true;
}
if(valid7){
if(data21.TimeshiftSupported !== undefined){
let data31 = data21.TimeshiftSupported;
const _errs66 = errors;
if((typeof data31 !== "boolean") && (data31 !== null)){
validate21.errors = [{instancePath:instancePath+"/Offerings/" + i2+"/TimeshiftSupported",schemaPath:"#/properties/Offerings/items/properties/TimeshiftSupported/type",keyword:"type",params:{type: schema32.properties.Offerings.items.properties.TimeshiftSupported.type},message:"must be boolean,null"}];
return false;
}
var valid7 = _errs66 === errors;
}
else {
var valid7 = true;
}
}
}
}
}
}
}
}
}
}
}
else {
validate21.errors = [{instancePath:instancePath+"/Offerings/" + i2,schemaPath:"#/properties/Offerings/items/type",keyword:"type",params:{type: "object"},message:"must be object"}];
return false;
}
}
var valid6 = _errs47 === errors;
if(!valid6){
break;
}
}
}
}
}
else {
validate21.errors = [{instancePath:instancePath+"/Offerings",schemaPath:"#/properties/Offerings/type",keyword:"type",params:{type: "array"},message:"must be array"}];
return false;
}
}
var valid0 = _errs45 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.FreshnessState !== undefined){
let data32 = data.FreshnessState;
const _errs68 = errors;
if(!((((data32 === "Current") || (data32 === "Stale")) || (data32 === "Unavailable")) || (data32 === "Unknown"))){
validate21.errors = [{instancePath:instancePath+"/FreshnessState",schemaPath:"#/properties/FreshnessState/enum",keyword:"enum",params:{allowedValues: schema32.properties.FreshnessState.enum},message:"must be equal to one of the allowed values"}];
return false;
}
var valid0 = _errs68 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.ConfidenceState !== undefined){
let data33 = data.ConfidenceState;
const _errs69 = errors;
if(!(((data33 === "Confirmed") || (data33 === "NeedsReview")) || (data33 === "Unknown"))){
validate21.errors = [{instancePath:instancePath+"/ConfidenceState",schemaPath:"#/properties/ConfidenceState/enum",keyword:"enum",params:{allowedValues: schema32.properties.ConfidenceState.enum},message:"must be equal to one of the allowed values"}];
return false;
}
var valid0 = _errs69 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.ConfidenceScore !== undefined){
let data34 = data.ConfidenceScore;
const _errs70 = errors;
if((!(((typeof data34 == "number") && (!(data34 % 1) && !isNaN(data34))) && (isFinite(data34)))) && (data34 !== null)){
validate21.errors = [{instancePath:instancePath+"/ConfidenceScore",schemaPath:"#/properties/ConfidenceScore/type",keyword:"type",params:{type: schema32.properties.ConfidenceScore.type},message:"must be integer,null"}];
return false;
}
if(errors === _errs70){
if((typeof data34 == "number") && (isFinite(data34))){
if(data34 > 100 || isNaN(data34)){
validate21.errors = [{instancePath:instancePath+"/ConfidenceScore",schemaPath:"#/properties/ConfidenceScore/maximum",keyword:"maximum",params:{comparison: "<=", limit: 100},message:"must be <= 100"}];
return false;
}
else {
if(data34 < 0 || isNaN(data34)){
validate21.errors = [{instancePath:instancePath+"/ConfidenceScore",schemaPath:"#/properties/ConfidenceScore/minimum",keyword:"minimum",params:{comparison: ">=", limit: 0},message:"must be >= 0"}];
return false;
}
}
}
}
var valid0 = _errs70 === errors;
}
else {
var valid0 = true;
}
}
}
}
}
}
}
}
}
}
}
}
}
}
}
}
}
}
}
}
}
}
}
}
else {
validate21.errors = [{instancePath,schemaPath:"#/type",keyword:"type",params:{type: "object"},message:"must be object"}];
return false;
}
}
validate21.errors = vErrors;
return errors === 0;
}
validate21.evaluated = {"props":true,"dynamicProps":false,"dynamicItems":false};


function validate20(data, {instancePath="", parentData, parentDataProperty, rootData=data, dynamicAnchors={}}={}){
/*# sourceURL="https://channelforge.invalid/schemas/one-guide-projection.schema.json" */;
let vErrors = null;
let errors = 0;
const evaluated0 = validate20.evaluated;
if(evaluated0.dynamicProps){
evaluated0.props = undefined;
}
if(evaluated0.dynamicItems){
evaluated0.items = undefined;
}
if(errors === 0){
if(data && typeof data == "object" && !Array.isArray(data)){
let missing0;
if(((((((((data.Version === undefined) && (missing0 = "Version")) || ((data.EvaluationTimeUtc === undefined) && (missing0 = "EvaluationTimeUtc"))) || ((data.Query === undefined) && (missing0 = "Query"))) || ((data.Offset === undefined) && (missing0 = "Offset"))) || ((data.MaximumItems === undefined) && (missing0 = "MaximumItems"))) || ((data.TotalCount === undefined) && (missing0 = "TotalCount"))) || ((data.ItemsTruncated === undefined) && (missing0 = "ItemsTruncated"))) || ((data.Items === undefined) && (missing0 = "Items"))){
validate20.errors = [{instancePath,schemaPath:"#/required",keyword:"required",params:{missingProperty: missing0},message:"must have required property '"+missing0+"'"}];
return false;
}
else {
const _errs1 = errors;
for(const key0 in data){
if(!(func1.call(schema31.properties, key0))){
validate20.errors = [{instancePath,schemaPath:"#/additionalProperties",keyword:"additionalProperties",params:{additionalProperty: key0},message:"must NOT have additional properties"}];
return false;
break;
}
}
if(_errs1 === errors){
if(data.Version !== undefined){
const _errs2 = errors;
if("one-guide/v1" !== data.Version){
validate20.errors = [{instancePath:instancePath+"/Version",schemaPath:"#/properties/Version/const",keyword:"const",params:{allowedValue: "one-guide/v1"},message:"must be equal to constant"}];
return false;
}
var valid0 = _errs2 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.EvaluationTimeUtc !== undefined){
let data1 = data.EvaluationTimeUtc;
const _errs3 = errors;
if(errors === _errs3){
if(errors === _errs3){
if(typeof data1 === "string"){
if(!(formats0.validate(data1))){
validate20.errors = [{instancePath:instancePath+"/EvaluationTimeUtc",schemaPath:"#/properties/EvaluationTimeUtc/format",keyword:"format",params:{format: "date-time"},message:"must match format \""+"date-time"+"\""}];
return false;
}
}
else {
validate20.errors = [{instancePath:instancePath+"/EvaluationTimeUtc",schemaPath:"#/properties/EvaluationTimeUtc/type",keyword:"type",params:{type: "string"},message:"must be string"}];
return false;
}
}
}
var valid0 = _errs3 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.Query !== undefined){
let data2 = data.Query;
const _errs5 = errors;
if(!((((data2 === "LiveNow") || (data2 === "StartingSoon")) || (data2 === "Category")) || (data2 === "Details"))){
validate20.errors = [{instancePath:instancePath+"/Query",schemaPath:"#/properties/Query/enum",keyword:"enum",params:{allowedValues: schema31.properties.Query.enum},message:"must be equal to one of the allowed values"}];
return false;
}
var valid0 = _errs5 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.CategoryKey !== undefined){
let data3 = data.CategoryKey;
const _errs6 = errors;
if(!(((((((((((((((((((((((data3 === "live-now") || (data3 === "starting-soon")) || (data3 === "football")) || (data3 === "baseball")) || (data3 === "basketball")) || (data3 === "hockey")) || (data3 === "soccer")) || (data3 === "wrestling")) || (data3 === "motorsports")) || (data3 === "boxing")) || (data3 === "mma")) || (data3 === "tennis")) || (data3 === "golf")) || (data3 === "rugby")) || (data3 === "cricket")) || (data3 === "lacrosse")) || (data3 === "other-sports")) || (data3 === "movies")) || (data3 === "news")) || (data3 === "kids")) || (data3 === "entertainment")) || (data3 === "documentary")) || (data3 === "comedy"))){
validate20.errors = [{instancePath:instancePath+"/CategoryKey",schemaPath:"#/properties/CategoryKey/enum",keyword:"enum",params:{allowedValues: schema31.properties.CategoryKey.enum},message:"must be equal to one of the allowed values"}];
return false;
}
var valid0 = _errs6 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.Offset !== undefined){
let data4 = data.Offset;
const _errs7 = errors;
if(!(((typeof data4 == "number") && (!(data4 % 1) && !isNaN(data4))) && (isFinite(data4)))){
validate20.errors = [{instancePath:instancePath+"/Offset",schemaPath:"#/properties/Offset/type",keyword:"type",params:{type: "integer"},message:"must be integer"}];
return false;
}
if(errors === _errs7){
if((typeof data4 == "number") && (isFinite(data4))){
if(data4 < 0 || isNaN(data4)){
validate20.errors = [{instancePath:instancePath+"/Offset",schemaPath:"#/properties/Offset/minimum",keyword:"minimum",params:{comparison: ">=", limit: 0},message:"must be >= 0"}];
return false;
}
}
}
var valid0 = _errs7 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.MaximumItems !== undefined){
let data5 = data.MaximumItems;
const _errs9 = errors;
if(!(((typeof data5 == "number") && (!(data5 % 1) && !isNaN(data5))) && (isFinite(data5)))){
validate20.errors = [{instancePath:instancePath+"/MaximumItems",schemaPath:"#/properties/MaximumItems/type",keyword:"type",params:{type: "integer"},message:"must be integer"}];
return false;
}
if(errors === _errs9){
if((typeof data5 == "number") && (isFinite(data5))){
if(data5 > 100 || isNaN(data5)){
validate20.errors = [{instancePath:instancePath+"/MaximumItems",schemaPath:"#/properties/MaximumItems/maximum",keyword:"maximum",params:{comparison: "<=", limit: 100},message:"must be <= 100"}];
return false;
}
else {
if(data5 < 1 || isNaN(data5)){
validate20.errors = [{instancePath:instancePath+"/MaximumItems",schemaPath:"#/properties/MaximumItems/minimum",keyword:"minimum",params:{comparison: ">=", limit: 1},message:"must be >= 1"}];
return false;
}
}
}
}
var valid0 = _errs9 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.TotalCount !== undefined){
let data6 = data.TotalCount;
const _errs11 = errors;
if(!(((typeof data6 == "number") && (!(data6 % 1) && !isNaN(data6))) && (isFinite(data6)))){
validate20.errors = [{instancePath:instancePath+"/TotalCount",schemaPath:"#/properties/TotalCount/type",keyword:"type",params:{type: "integer"},message:"must be integer"}];
return false;
}
if(errors === _errs11){
if((typeof data6 == "number") && (isFinite(data6))){
if(data6 < 0 || isNaN(data6)){
validate20.errors = [{instancePath:instancePath+"/TotalCount",schemaPath:"#/properties/TotalCount/minimum",keyword:"minimum",params:{comparison: ">=", limit: 0},message:"must be >= 0"}];
return false;
}
}
}
var valid0 = _errs11 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.ItemsTruncated !== undefined){
const _errs13 = errors;
if(typeof data.ItemsTruncated !== "boolean"){
validate20.errors = [{instancePath:instancePath+"/ItemsTruncated",schemaPath:"#/properties/ItemsTruncated/type",keyword:"type",params:{type: "boolean"},message:"must be boolean"}];
return false;
}
var valid0 = _errs13 === errors;
}
else {
var valid0 = true;
}
if(valid0){
if(data.Items !== undefined){
let data8 = data.Items;
const _errs15 = errors;
if(errors === _errs15){
if(Array.isArray(data8)){
if(data8.length > 100){
validate20.errors = [{instancePath:instancePath+"/Items",schemaPath:"#/properties/Items/maxItems",keyword:"maxItems",params:{limit: 100},message:"must NOT have more than 100 items"}];
return false;
}
else {
var valid1 = true;
const len0 = data8.length;
for(let i0=0; i0<len0; i0++){
const _errs17 = errors;
if(!(validate21(data8[i0], {instancePath:instancePath+"/Items/" + i0,parentData:data8,parentDataProperty:i0,rootData,dynamicAnchors}))){
vErrors = vErrors === null ? validate21.errors : vErrors.concat(validate21.errors);
errors = vErrors.length;
}
var valid1 = _errs17 === errors;
if(!valid1){
break;
}
}
}
}
else {
validate20.errors = [{instancePath:instancePath+"/Items",schemaPath:"#/properties/Items/type",keyword:"type",params:{type: "array"},message:"must be array"}];
return false;
}
}
var valid0 = _errs15 === errors;
}
else {
var valid0 = true;
}
}
}
}
}
}
}
}
}
}
}
}
else {
validate20.errors = [{instancePath,schemaPath:"#/type",keyword:"type",params:{type: "object"},message:"must be object"}];
return false;
}
}
validate20.errors = vErrors;
return errors === 0;
}
validate20.evaluated = {"props":true,"dynamicProps":false,"dynamicItems":false};

