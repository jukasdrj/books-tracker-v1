#!/usr/bin/env node
/**
 * Test Script for Enhanced ISBNdb Worker - All 4 Proven Patterns
 * 
 * Tests the enhanced CloudFlare worker with the validated ISBNdb patterns
 * to ensure >90% success rate with comprehensive pattern coverage.
 */

const WORKER_URL = 'https://isbndb-test.books.ooheynerds.com';
// const WORKER_URL = 'http://localhost:8787'; // For local testing

const TEST_CASES = {
  // Pattern 1: Author works in English
  authorSearch: [
    {
      name: 'Andy Weir - Standard',
      url: `/author/andy%20weir?language=en&pageSize=20`,
      expectedBooks: 5, // Conservative estimate
      description: 'Popular sci-fi author with known works'
    },
    {
      name: 'Stephen King - High Volume',
      url: `/author/stephen%20king?language=en&pageSize=50&page=1`,
      expectedBooks: 30, // Prolific author
      description: 'Prolific horror author with extensive bibliography'
    },
    {
      name: 'Emily Henry - Contemporary',
      url: `/author/emily%20henry?language=en&pageSize=25`,
      expectedBooks: 8, // Newer author with several popular books
      description: 'Contemporary romance author'
    }
  ],

  // Pattern 2: Book by ISBN
  isbnLookup: [
    {
      name: 'The Martian - ISBN13',
      url: `/book/9780553418026?with_prices=0`,
      expectedTitle: 'The Martian',
      expectedAuthor: 'Andy Weir',
      description: 'Popular sci-fi novel, well-known ISBN'
    },
    {
      name: 'A Little Life - ISBN13',
      url: `/book/9780385539258?with_prices=0`,
      expectedTitle: 'A Little Life',
      expectedAuthor: 'Hanya Yanagihara',
      description: 'Award-winning literary fiction'
    },
    {
      name: 'Project Hail Mary - ISBN10',
      url: `/book/0593135202?with_prices=0`,
      expectedTitle: 'Project Hail Mary',
      expectedAuthor: 'Andy Weir',
      description: 'Recent bestseller with ISBN-10 format'
    }
  ],

  // Pattern 3: Title search
  titleSearch: [
    {
      name: 'Exact Title - A Little Life',
      url: `/books/a%20little%20life?column=title&language=en&shouldMatchAll=1&pageSize=10`,
      expectedTitle: 'A Little Life',
      description: 'Exact title match with proper filtering'
    },
    {
      name: 'Exact Title - The Seven Husbands',
      url: `/books/the%20seven%20husbands%20of%20evelyn%20hugo?column=title&language=en&shouldMatchAll=1&pageSize=10`,
      expectedTitle: 'The Seven Husbands of Evelyn Hugo',
      description: 'Longer title with exact matching'
    },
    {
      name: 'Simple Title - Educated',
      url: `/books/educated?column=title&language=en&shouldMatchAll=1&pageSize=15`,
      expectedTitle: 'Educated',
      description: 'Single word title search'
    }
  ],

  // Pattern 4: Combined search
  combinedSearch: [
    {
      name: 'Author + Title - Andy Weir + Martian',
      url: `/search/books?author=andy%20weir&text=the%20martian&pageSize=20`,
      expectedAuthor: 'Andy Weir',
      expectedTitleContains: 'Martian',
      description: 'Combined author and title search'
    },
    {
      name: 'Author + Publisher - King + Scribner',
      url: `/search/books?author=stephen%20king&publisher=scribner&pageSize=25`,
      expectedAuthor: 'Stephen King',
      description: 'Author with specific publisher filter'
    },
    {
      name: 'Text Only - Artemis',
      url: `/search/books?text=artemis&pageSize=15`,
      expectedTitleContains: 'Artemis',
      description: 'Text-only search for specific title'
    }
  ]
};

/**
 * Test runner with comprehensive pattern validation
 */
async function runAllTests() {
  console.log('🚀 Starting Enhanced ISBNdb Worker Tests');
  console.log('=' .repeat(60));
  
  const results = {
    total: 0,
    passed: 0,
    failed: 0,
    patterns: {
      authorSearch: { total: 0, passed: 0 },
      isbnLookup: { total: 0, passed: 0 },
      titleSearch: { total: 0, passed: 0 },
      combinedSearch: { total: 0, passed: 0 }
    }
  };

  // Test Pattern 1: Author Search
  console.log('📚 Testing Pattern 1: Author Search');
  console.log('-'.repeat(40));
  for (const test of TEST_CASES.authorSearch) {
    const result = await testAuthorSearch(test);
    updateResults(results, 'authorSearch', result);
  }

  // Test Pattern 2: ISBN Lookup
  console.log('\n📖 Testing Pattern 2: ISBN Lookup');
  console.log('-'.repeat(40));
  for (const test of TEST_CASES.isbnLookup) {
    const result = await testIsbnLookup(test);
    updateResults(results, 'isbnLookup', result);
  }

  // Test Pattern 3: Title Search
  console.log('\n🔍 Testing Pattern 3: Title Search');
  console.log('-'.repeat(40));
  for (const test of TEST_CASES.titleSearch) {
    const result = await testTitleSearch(test);
    updateResults(results, 'titleSearch', result);
  }

  // Test Pattern 4: Combined Search
  console.log('\n🎯 Testing Pattern 4: Combined Search');
  console.log('-'.repeat(40));
  for (const test of TEST_CASES.combinedSearch) {
    const result = await testCombinedSearch(test);
    updateResults(results, 'combinedSearch', result);
  }

  // Health Check
  console.log('\n❤️  Testing Health Check');
  console.log('-'.repeat(40));
  const healthResult = await testHealthCheck();
  updateResults(results, 'health', healthResult);

  // Final Results
  console.log('\n📊 TEST RESULTS SUMMARY');
  console.log('=' .repeat(60));
  console.log(`Overall: ${results.passed}/${results.total} (${(results.passed/results.total*100).toFixed(1)}%)`);
  
  Object.entries(results.patterns).forEach(([pattern, stats]) => {
    const percentage = stats.total > 0 ? (stats.passed/stats.total*100).toFixed(1) : 'N/A';
    console.log(`${pattern}: ${stats.passed}/${stats.total} (${percentage}%)`);
  });

  const overallSuccess = (results.passed / results.total) * 100;
  if (overallSuccess >= 90) {
    console.log(`\n✅ SUCCESS: ${overallSuccess.toFixed(1)}% success rate meets >90% target`);
  } else {
    console.log(`\n❌ FAILED: ${overallSuccess.toFixed(1)}% success rate below 90% target`);
  }

  return results;
}

/**
 * Test Pattern 1: Author Search
 */
async function testAuthorSearch(test) {
  try {
    console.log(`Testing: ${test.name}`);
    
    const response = await fetch(`${WORKER_URL}${test.url}`);
    const data = await response.json();
    
    if (!response.ok) {
      console.log(`❌ FAILED: ${test.name} - HTTP ${response.status}`);
      console.log(`   Error: ${data.error || 'Unknown error'}`);
      return false;
    }
    
    if (!data.success || !data.books || data.books.length < test.expectedBooks) {
      console.log(`❌ FAILED: ${test.name} - Expected ${test.expectedBooks}+ books, got ${data.books?.length || 0}`);
      return false;
    }
    
    // Validate book structure
    const firstBook = data.books[0];
    if (!firstBook.title || !firstBook.authors) {
      console.log(`❌ FAILED: ${test.name} - Invalid book structure`);
      return false;
    }
    
    console.log(`✅ PASSED: ${test.name} - Found ${data.books.length} books`);
    console.log(`   Sample: "${firstBook.title}" by ${firstBook.authors.join(', ')}`);
    return true;
    
  } catch (error) {
    console.log(`❌ ERROR: ${test.name} - ${error.message}`);
    return false;
  }
}

/**
 * Test Pattern 2: ISBN Lookup
 */
async function testIsbnLookup(test) {
  try {
    console.log(`Testing: ${test.name}`);
    
    const response = await fetch(`${WORKER_URL}${test.url}`);
    const data = await response.json();
    
    if (!response.ok) {
      console.log(`❌ FAILED: ${test.name} - HTTP ${response.status}`);
      return false;
    }
    
    if (!data.success || !data.book) {
      console.log(`❌ FAILED: ${test.name} - No book data returned`);
      return false;
    }
    
    const book = data.book;
    const titleMatch = book.title && book.title.toLowerCase().includes(test.expectedTitle.toLowerCase());
    const authorMatch = book.authors && book.authors.some(author => 
      author.toLowerCase().includes(test.expectedAuthor.toLowerCase())
    );
    
    if (!titleMatch || !authorMatch) {
      console.log(`❌ FAILED: ${test.name} - Title/Author mismatch`);
      console.log(`   Expected: "${test.expectedTitle}" by ${test.expectedAuthor}`);
      console.log(`   Got: "${book.title}" by ${book.authors?.join(', ')}`);
      return false;
    }
    
    console.log(`✅ PASSED: ${test.name} - "${book.title}" by ${book.authors.join(', ')}`);
    return true;
    
  } catch (error) {
    console.log(`❌ ERROR: ${test.name} - ${error.message}`);
    return false;
  }
}

/**
 * Test Pattern 3: Title Search
 */
async function testTitleSearch(test) {
  try {
    console.log(`Testing: ${test.name}`);
    
    const response = await fetch(`${WORKER_URL}${test.url}`);
    const data = await response.json();
    
    if (!response.ok) {
      console.log(`❌ FAILED: ${test.name} - HTTP ${response.status}`);
      return false;
    }
    
    if (!data.success || !data.books || data.books.length === 0) {
      console.log(`❌ FAILED: ${test.name} - No books found`);
      return false;
    }
    
    const hasExpectedTitle = data.books.some(book => 
      book.title && book.title.toLowerCase().includes(test.expectedTitle.toLowerCase())
    );
    
    if (!hasExpectedTitle) {
      console.log(`❌ FAILED: ${test.name} - Expected title not found`);
      console.log(`   Looking for: "${test.expectedTitle}"`);
      console.log(`   Found titles: ${data.books.map(b => `"${b.title}"`).join(', ')}`);
      return false;
    }
    
    console.log(`✅ PASSED: ${test.name} - Found ${data.books.length} books including expected title`);
    return true;
    
  } catch (error) {
    console.log(`❌ ERROR: ${test.name} - ${error.message}`);
    return false;
  }
}

/**
 * Test Pattern 4: Combined Search
 */
async function testCombinedSearch(test) {
  try {
    console.log(`Testing: ${test.name}`);
    
    const response = await fetch(`${WORKER_URL}${test.url}`);
    const data = await response.json();
    
    if (!response.ok) {
      console.log(`❌ FAILED: ${test.name} - HTTP ${response.status}`);
      return false;
    }
    
    if (!data.success || !data.books || data.books.length === 0) {
      console.log(`❌ FAILED: ${test.name} - No books found`);
      return false;
    }
    
    // Check author match if expected
    if (test.expectedAuthor) {
      const hasExpectedAuthor = data.books.some(book => 
        book.authors && book.authors.some(author =>
          author.toLowerCase().includes(test.expectedAuthor.toLowerCase())
        )
      );
      
      if (!hasExpectedAuthor) {
        console.log(`❌ FAILED: ${test.name} - Expected author not found`);
        return false;
      }
    }
    
    // Check title contains if expected
    if (test.expectedTitleContains) {
      const hasTitleMatch = data.books.some(book => 
        book.title && book.title.toLowerCase().includes(test.expectedTitleContains.toLowerCase())
      );
      
      if (!hasTitleMatch) {
        console.log(`❌ FAILED: ${test.name} - Expected title content not found`);
        return false;
      }
    }
    
    console.log(`✅ PASSED: ${test.name} - Found ${data.books.length} relevant books`);
    return true;
    
  } catch (error) {
    console.log(`❌ ERROR: ${test.name} - ${error.message}`);
    return false;
  }
}

/**
 * Test Health Check
 */
async function testHealthCheck() {
  try {
    console.log('Testing: Health Check');
    
    const response = await fetch(`${WORKER_URL}/health`);
    const data = await response.json();
    
    if (!response.ok || data.status !== 'healthy') {
      console.log(`❌ FAILED: Health Check - Status: ${data.status || 'unhealthy'}`);
      return false;
    }
    
    const requiredServices = ['kv', 'r2', 'isbndb'];
    const serviceStatus = data.services || {};
    
    for (const service of requiredServices) {
      if (!serviceStatus[service] || serviceStatus[service] === 'missing') {
        console.log(`❌ FAILED: Health Check - ${service} service not properly configured`);
        return false;
      }
    }
    
    console.log(`✅ PASSED: Health Check - All services healthy`);
    console.log(`   Version: ${data.version}, Patterns: ${Object.keys(data.patterns || {}).length}`);
    return true;
    
  } catch (error) {
    console.log(`❌ ERROR: Health Check - ${error.message}`);
    return false;
  }
}

/**
 * Update test results tracking
 */
function updateResults(results, pattern, passed) {
  results.total++;
  if (passed) results.passed++;
  else results.failed++;
  
  if (results.patterns[pattern]) {
    results.patterns[pattern].total++;
    if (passed) results.patterns[pattern].passed++;
  }
}

// Add delay between requests to respect rate limiting
function delay(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// Run tests if called directly
if (require.main === module) {
  runAllTests()
    .then(results => {
      const successRate = (results.passed / results.total) * 100;
      process.exit(successRate >= 90 ? 0 : 1);
    })
    .catch(error => {
      console.error('Test suite failed:', error);
      process.exit(1);
    });
}

module.exports = { runAllTests, TEST_CASES };