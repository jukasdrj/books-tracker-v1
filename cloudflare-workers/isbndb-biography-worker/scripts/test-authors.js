#!/usr/bin/env node

/**
 * Test script for Phase 1 ISBNdb Biography Worker
 * Tests all 5 required authors for >90% success rate validation
 */

const TEST_AUTHORS = [
  'andy weir',
  'emily henry', 
  'stephen king',
  'kristin hannah',
  'amor towles'
];

const BASE_URL = 'https://isbndb-test.books.ooheynerds.com';

async function testAuthor(authorName) {
  const startTime = Date.now();
  
  try {
    console.log(`\n🔍 Testing: ${authorName}`);
    
    const response = await fetch(`${BASE_URL}/author/${encodeURIComponent(authorName)}`);
    const responseTime = Date.now() - startTime;
    
    if (!response.ok) {
      console.log(`❌ FAIL: ${response.status} - ${response.statusText}`);
      return { success: false, author: authorName, error: `HTTP ${response.status}`, responseTime };
    }
    
    const data = await response.json();
    
    if (data.success && data.books && data.books.length > 0) {
      console.log(`✅ SUCCESS: Found ${data.books.length} books in ${responseTime}ms`);
      console.log(`   📚 Sample books: ${data.books.slice(0, 3).map(b => b.title).join(', ')}`);
      console.log(`   💾 Cached: ${data.cached ? 'Yes' : 'No'}`);
      
      return { 
        success: true, 
        author: authorName, 
        booksCount: data.books.length, 
        responseTime,
        cached: data.cached
      };
    } else {
      console.log(`❌ FAIL: No books found or invalid response`);
      return { success: false, author: authorName, error: 'No books found', responseTime };
    }
    
  } catch (error) {
    const responseTime = Date.now() - startTime;
    console.log(`❌ ERROR: ${error.message}`);
    return { success: false, author: authorName, error: error.message, responseTime };
  }
}

async function testHealthCheck() {
  try {
    console.log(`\n🏥 Testing health check...`);
    
    const response = await fetch(`${BASE_URL}/health`);
    
    if (response.ok) {
      const data = await response.json();
      console.log(`✅ Health check passed`);
      console.log(`   Services: KV=${data.services?.kv}, R2=${data.services?.r2}, ISBNdb=${data.services?.isbndb}`);
      return true;
    } else {
      console.log(`❌ Health check failed: ${response.status}`);
      return false;
    }
  } catch (error) {
    console.log(`❌ Health check error: ${error.message}`);
    return false;
  }
}

async function runTests() {
  console.log('🚀 ISBNdb Biography Worker - Phase 1 Testing');
  console.log(`📍 Testing endpoint: ${BASE_URL}`);
  console.log(`🎯 Success target: >90% (${Math.ceil(TEST_AUTHORS.length * 0.9)}/${TEST_AUTHORS.length} authors)`);
  
  // Test health check first
  const healthOk = await testHealthCheck();
  if (!healthOk) {
    console.log('\n⚠️  Health check failed, but continuing with author tests...');
  }
  
  // Test all authors
  const results = [];
  
  for (const author of TEST_AUTHORS) {
    const result = await testAuthor(author);
    results.push(result);
    
    // Wait between requests to respect rate limiting
    if (TEST_AUTHORS.indexOf(author) < TEST_AUTHORS.length - 1) {
      await new Promise(resolve => setTimeout(resolve, 1200));
    }
  }
  
  // Calculate results
  const successful = results.filter(r => r.success);
  const successRate = (successful.length / results.length) * 100;
  const avgResponseTime = results.reduce((sum, r) => sum + r.responseTime, 0) / results.length;
  
  console.log('\n📊 RESULTS SUMMARY');
  console.log('═'.repeat(50));
  console.log(`✅ Successful: ${successful.length}/${results.length} authors`);
  console.log(`📈 Success rate: ${successRate.toFixed(1)}%`);
  console.log(`⚡ Avg response time: ${Math.round(avgResponseTime)}ms`);
  console.log(`🎯 Target: >90% (${successRate >= 90 ? 'ACHIEVED' : 'NOT MET'})`);
  
  // Show failures
  const failed = results.filter(r => !r.success);
  if (failed.length > 0) {
    console.log('\n❌ FAILURES:');
    failed.forEach(f => {
      console.log(`   ${f.author}: ${f.error} (${f.responseTime}ms)`);
    });
  }
  
  // Show successful details
  if (successful.length > 0) {
    console.log('\n✅ SUCCESSFUL AUTHORS:');
    successful.forEach(s => {
      console.log(`   ${s.author}: ${s.booksCount} books (${s.responseTime}ms, cached: ${s.cached})`);
    });
  }
  
  console.log('\n' + '═'.repeat(50));
  
  if (successRate >= 90) {
    console.log('🎉 PHASE 1 SUCCESS! Ready to proceed to Phase 2.');
    process.exit(0);
  } else {
    console.log('⚠️  PHASE 1 INCOMPLETE. Address failures before Phase 2.');
    process.exit(1);
  }
}

// Run tests if called directly
if (require.main === module) {
  runTests().catch(error => {
    console.error('Test suite error:', error);
    process.exit(1);
  });
}

module.exports = { testAuthor, testHealthCheck, runTests };